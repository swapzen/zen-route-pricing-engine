# H3 Hexagonal Mapping System Plan

## Status: PROPOSAL
## City: Hyderabad (HYD) — pilot, scalable to all cities
## Date: 2026-03-12

---

## 1. Problem Statement

The pricing engine currently resolves zones using **bounding box (bbox)** checks — iterating through all 55+ zones per lookup with `Zone#contains_point_bbox?`.

| Problem | Impact |
|---------|--------|
| **O(n) linear scan** per zone lookup | 55+ comparisons per quote for HYD |
| **Overlapping bboxes** (rectangles don't tile) | Ambiguous zone assignment at boundaries |
| **No spatial index** | CockroachDB spatial queries are TODO |
| **Doesn't scale** | Adding cities multiplies the problem |
| **Poor boundary precision** | Rectangles poorly represent real neighborhoods |

The critical code path is `ZonePricingResolver#find_zone` (line 430-440) which loads all zones and iterates:

```ruby
def find_zone(city_code, lat, lng)
  @zones_cache[city_code].each do |z|
    return z if z.contains_point?(lat, lng)  # O(n) per call
  end
end
```

---

## 2. Solution: H3 Hexagonal Spatial Index

Uber's H3 provides **O(1) constant-time** point-to-zone resolution via a mathematical hash function. A lat/lng becomes a 64-bit integer instantly — no geometry, no spatial queries, no iteration.

### Architecture Comparison

```
                    CURRENT                              WITH H3
                    -------                              -------
    lat/lng                                   lat/lng
      |                                         |
      v                                         v
  Load all zones (DB)                    H3.lat_lng_to_cell(res=8)   <-- O(1), no DB
      |                                         |
      v                                         v
  Iterate 55+ zones                      Redis/Memory lookup         <-- O(1)
  contains_point_bbox?                    hex_index -> zone_id
      |                                         |
      v                                         v
  Zone found (maybe)                     Zone found (deterministic)
      |                                         |
      v                                         v
  ZonePricingResolver                    ZonePricingResolver (unchanged)
  (5-tier hierarchy)                     (5-tier hierarchy preserved)
```

---

## 3. H3 Resolution Choice

| Resolution | Hex Area | Edge Length | Use in Engine |
|-----------|----------|-------------|---------------|
| **Res 7** | ~5.16 km2 | ~1.22 km | City-level fallback, inter-zone grouping |
| **Res 8** | ~0.74 km2 | ~0.46 km | **Primary zone mapping** (replaces bbox) |
| **Res 9** | ~0.11 km2 | ~0.17 km | Future surge pricing granularity |

**Decision: Resolution 8 as primary.**

Each Res 8 hex covers ~0.74 km2 (roughly one neighborhood block). Hyderabad's GHMC area (~650 km2) needs ~880 hexes at Res 8. This maps well to 55 zones (avg ~16 hexes per zone). Small enough for precision, large enough to keep the mapping table manageable.

---

## 4. Implementation Phases

### Phase 1: Foundation (Week 1-2) -- Non-Breaking

#### 1a. Add `h3` gem

```ruby
# Gemfile
gem 'h3', '~> 3.7'  # Ruby bindings for Uber's H3 (FFI to C library)
```

#### 1b. New Table: `h3_zone_mappings`

```ruby
# db/migrate/XXXXXXXX_create_h3_zone_mappings.rb
class CreateH3ZoneMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :h3_zone_mappings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :h3_index,      null: false  # e.g., "886820d20ffffff"
      t.integer  :h3_resolution,  null: false, default: 8
      t.uuid     :zone_id,       null: false
      t.string   :city_code,     null: false  # e.g., "hyd"
      t.string   :zone_code,     null: false  # e.g., "hitech_madhapur"
      t.boolean  :is_boundary,   default: false  # true for edge hexes
      t.float    :coverage_pct   # % of hex area within zone polygon (for boundaries)
      t.boolean  :active,        default: true
      t.timestamps
    end

    add_index :h3_zone_mappings, [:city_code, :h3_index], unique: true
    add_index :h3_zone_mappings, [:zone_id]
    add_index :h3_zone_mappings, [:city_code, :zone_code]
    add_index :h3_zone_mappings, [:h3_index]
  end
end
```

#### 1c. ALTER TABLE on `zones` (add H3 metadata columns)

```ruby
# db/migrate/XXXXXXXX_add_h3_columns_to_zones.rb
class AddH3ColumnsToZones < ActiveRecord::Migration[8.0]
  def change
    add_column :zones, :h3_center_index, :string     # Center hex at res 8
    add_column :zones, :h3_resolution, :integer, default: 8
    add_column :zones, :h3_hex_count, :integer        # Number of hexes in zone
    add_column :zones, :h3_enabled, :boolean, default: false
  end
end
```

#### 1d. New Model: `H3ZoneMapping`

```ruby
# app/models/h3_zone_mapping.rb
class H3ZoneMapping < ApplicationRecord
  belongs_to :zone

  validates :h3_index, presence: true, uniqueness: { scope: :city_code }
  validates :city_code, presence: true
  validates :zone_code, presence: true

  scope :active, -> { where(active: true) }
  scope :for_city, ->(city_code) { where(city_code: city_code.to_s.downcase) }
  scope :boundaries, -> { where(is_boundary: true) }
end
```

#### 1e. New Service: `H3ZoneResolver`

```ruby
# app/services/route_pricing/services/h3_zone_resolver.rb
module RoutePricing
  module Services
    class H3ZoneResolver
      RESOLUTION = 8
      CACHE_KEY_PREFIX = "h3_zone_map"
      CACHE_TTL = 2.hours

      def initialize(city_code)
        @city_code = city_code.to_s.downcase
      end

      # O(1) zone lookup -- replaces O(n) bbox iteration
      def find_zone(lat, lng)
        h3_index = H3.from_geo_coordinates([lat.to_f, lng.to_f], RESOLUTION)
        zone_id = lookup_zone_for_hex(h3_index)

        # Boundary fallback: check k-ring(1) neighbors if unmapped
        if zone_id.nil?
          neighbors = H3.k_ring(h3_index, 1)
          neighbors.each do |neighbor_hex|
            zone_id = lookup_zone_for_hex(neighbor_hex)
            break if zone_id
          end
        end

        return nil unless zone_id
        Zone.find_by(id: zone_id)
      end

      # Build the hex -> zone_id map for a city
      def self.build_city_map(city_code)
        map = {}
        H3ZoneMapping.where(city_code: city_code, active: true).find_each do |mapping|
          map[mapping.h3_index] = mapping.zone_id
        end

        cache_key = "#{CACHE_KEY_PREFIX}:#{city_code}"
        Rails.cache.write(cache_key, map, expires_in: CACHE_TTL)
        map
      end

      private

      def lookup_zone_for_hex(h3_index)
        city_map[h3_index.is_a?(Integer) ? h3_index.to_s(16) : h3_index]
      end

      def city_map
        @city_map ||= begin
          cache_key = "#{CACHE_KEY_PREFIX}:#{@city_code}"
          cached = Rails.cache.read(cache_key)
          return cached if cached

          self.class.build_city_map(@city_code)
        end
      end
    end
  end
end
```

#### 1f. Seed Task: Convert bbox -> H3 hexagons

```ruby
# lib/tasks/h3_zones.rake
namespace :h3 do
  desc "Generate H3 hex mappings from zone bounding boxes"
  task seed: :environment do
    require 'h3'

    city_code = ENV['CITY'] || 'hyd'
    resolution = (ENV['RES'] || 8).to_i

    zones = Zone.for_city(city_code).active
    total_hexes = 0

    zones.each do |zone|
      next unless zone.lat_min && zone.lat_max && zone.lng_min && zone.lng_max

      # Generate polygon from bbox corners
      polygon = [
        [zone.lat_min, zone.lng_min],
        [zone.lat_min, zone.lng_max],
        [zone.lat_max, zone.lng_max],
        [zone.lat_max, zone.lng_min],
        [zone.lat_min, zone.lng_min]  # close polygon
      ]

      # Polyfill: get all H3 hexagons covering this bbox
      hexagons = H3.polyfill(polygon, resolution)

      # Ensure center hex is included
      center_lat = (zone.lat_min + zone.lat_max) / 2.0
      center_lng = (zone.lng_min + zone.lng_max) / 2.0
      center_hex = H3.from_geo_coordinates([center_lat, center_lng], resolution)
      hexagons << center_hex unless hexagons.include?(center_hex)

      hexagons.each do |hex|
        hex_str = hex.to_s(16)
        H3ZoneMapping.find_or_create_by!(
          city_code: city_code,
          h3_index: hex_str
        ) do |m|
          m.zone_id = zone.id
          m.zone_code = zone.zone_code
          m.h3_resolution = resolution
          m.is_boundary = H3.k_ring(hex, 1).any? { |n| !hexagons.include?(n) }
        end
      end

      zone.update!(
        h3_center_index: center_hex.to_s(16),
        h3_resolution: resolution,
        h3_hex_count: hexagons.size,
        h3_enabled: true
      )

      total_hexes += hexagons.size
      puts "  #{zone.zone_code}: #{hexagons.size} hexes"
    end

    RoutePricing::Services::H3ZoneResolver.build_city_map(city_code)
    puts "\nTotal: #{total_hexes} hexes for #{zones.count} zones"
  end
end
```

---

### Phase 2: Dual-Mode Integration (Week 2-3)

#### 2a. Update `ZonePricingResolver#find_zone` with H3 fast path

```ruby
# In zone_pricing_resolver.rb -- replace find_zone method
def find_zone(city_code, lat, lng)
  # Fast path: H3 lookup (O(1))
  if h3_enabled?(city_code)
    zone = h3_resolver(city_code).find_zone(lat, lng)
    return zone if zone
    # H3 miss -> fall through to bbox (boundary edge case)
  end

  # Slow path: Original bbox iteration (fallback)
  @zones_cache ||= {}
  @zones_cache[city_code] ||= Zone.for_city(city_code).active
    .order(priority: :desc, zone_code: :asc).to_a

  @zones_cache[city_code].each do |z|
    return z if z.contains_point?(lat, lng)
  end
  nil
end

private

def h3_enabled?(city_code)
  @h3_enabled ||= {}
  @h3_enabled[city_code] ||= H3ZoneMapping.where(city_code: city_code, active: true).exists?
end

def h3_resolver(city_code)
  @h3_resolvers ||= {}
  @h3_resolvers[city_code] ||= H3ZoneResolver.new(city_code)
end
```

#### 2b. Enhanced Redis Cache Keys with H3

```ruby
# In CacheKeyBuilder -- add H3-aware key generation
def build_h3_zone_key(city_code:, h3_index:, vehicle_type:, time_band:)
  time_bucket = (Time.current.to_i / 7200) # 2-hour bucket
  "zp:h3:#{city_code}:#{h3_index}:#{vehicle_type}:#{time_band}:#{time_bucket}"
end
```

H3 bucketing means identical hex lookups within a 2-hour window share cache entries -- far more efficient than lat/lng-based keys where slight coordinate differences cause cache misses.

---

### Phase 3: YAML Config Extension (Week 3)

Extend YAML format (backward compatible):

```yaml
# config/zones/hyderabad.yml
zones:
  hitech_madhapur:
    name: "HITEC City & Madhapur Hub"
    zone_type: tech_corridor
    active: true
    bounds:                          # KEPT for backward compatibility
      lat_min: 17.43
      lat_max: 17.455
      lng_min: 78.37
      lng_max: 78.41
    h3:                              # NEW -- H3 spatial definition
      resolution: 8
      center: "886a5c469ffffff"
      hexagons:                      # Auto-generated by rake h3:seed
        - "886a5c469ffffff"
        - "886a5c461ffffff"
        - "886a5c463ffffff"
      boundary_hexagons:
        - "886a5c463ffffff"
    multipliers:
      small_vehicle: 1.0
      mid_truck: 1.0
      heavy_truck: 1.0
      default: 1.0
```

---

### Phase 4: Performance Optimization (Week 4)

#### 4a. In-Memory H3 Map (eliminate Redis for hot path)

```ruby
class H3ZoneResolver
  # Entire city map fits in process memory
  # HYD = ~880 hexes x 30 bytes = ~26 KB
  @@city_maps = {}
  @@map_loaded_at = {}

  def city_map
    @city_map ||= begin
      if stale?(@city_code)
        @@city_maps[@city_code] = load_from_db
        @@map_loaded_at[@city_code] = Time.current
      end
      @@city_maps[@city_code]
    end
  end

  def stale?(city_code)
    !@@map_loaded_at[city_code] ||
      (Time.current - @@map_loaded_at[city_code]) > 2.hours
  end
end
```

#### 4b. Performance Targets

| Metric | Current (bbox) | Target (H3) | Improvement |
|--------|---------------|-------------|-------------|
| Zone lookup | ~2-5ms (55 iterations) | ~0.01ms (hash + memory) | **200-500x** |
| Multi-quote (7 vehicles) | ~14-35ms zone resolution | ~0.07ms | **200x** |
| Redis cache hit rate | ~60% (lat/lng variance) | ~95% (hex bucketing) | **+35%** |
| Memory per city | ~55 Zone AR objects | ~26 KB hash map | **90% less** |
| Adding a new city | Load time grows linearly | Constant per city | **O(1)** |

---

### Phase 5: Surge Pricing per Hex (Week 5+)

#### 5a. New Table: `h3_surge_buckets`

```ruby
create_table :h3_surge_buckets, id: :uuid do |t|
  t.string  :h3_index, null: false       # Res 9 for surge granularity
  t.string  :city_code, null: false
  t.integer :h3_resolution, default: 9
  t.float   :demand_score               # Real-time demand signal
  t.float   :supply_score               # Driver availability
  t.float   :surge_multiplier, default: 1.0
  t.string  :time_band                  # morning/afternoon/evening
  t.datetime :expires_at
  t.timestamps
end

add_index :h3_surge_buckets, [:city_code, :h3_index, :time_band], unique: true
```

#### 5b. Real-time surge flow

```
Customer request (lat/lng)
    |
    v
H3.from_geo_coordinates(res=9)  ->  hex "896a5c460ffffff"
    |
    v
Redis: surge:{city}:{hex}:{time_band}  ->  1.3x multiplier
    |
    v
PriceCalculator applies surge_multiplier to raw_subtotal
```

This enables **Uber-style hyperlocal surge pricing** -- different blocks in HITEC City can have different surge levels based on real-time demand.

---

## 5. Boundary Handling Strategy

For hexes that straddle two zones (edge hexes):

1. **Primary assignment**: Hex center point determines zone (deterministic)
2. **Boundary flag**: `is_boundary: true` marks edge hexes in DB
3. **Priority resolution**: If a boundary hex could belong to a higher-priority zone, assign it there (matches current `priority: :desc` ordering)
4. **K-ring fallback**: If a point maps to an unmapped hex (gap between zones), check the 6 neighbors

This eliminates overlapping bboxes where a point could match multiple zones.

---

## 6. Multi-City Scaling

The entire system is city-code scoped. Adding a new city:

1. Create `config/zones/{city}.yml` with bbox bounds
2. Run `rake h3:seed CITY=blr` -- auto-generates hex mappings
3. Redis/memory cache auto-populates on first request

**No code changes needed per city.**

| City | Estimated Hexes (Res 8) | Memory |
|------|------------------------|--------|
| Hyderabad | ~880 | ~26 KB |
| Bangalore | ~750 | ~22 KB |
| Mumbai | ~600 | ~18 KB |
| Delhi NCR | ~1,500 | ~45 KB |
| All 6 cities | ~5,000 | ~150 KB |

---

## 7. Verification Checklist

- [ ] Add `h3` gem to Gemfile
- [ ] Create `h3_zone_mappings` table migration
- [ ] ALTER TABLE zones (add h3 columns) migration
- [ ] Create `H3ZoneMapping` model
- [ ] Create `H3ZoneResolver` service
- [ ] Create `rake h3:seed` task
- [ ] Update `ZonePricingResolver#find_zone` (dual-mode)
- [ ] Seed HYD hexes and verify against existing zone assignments
- [ ] Run `script/test_pricing_engine.rb` -- all 210 scenarios must pass unchanged
- [ ] Enable H3 fast path, keep bbox fallback
- [ ] Monitor Redis hit rates and latency improvements
- [ ] Extend YAML format with H3 metadata
- [ ] Create `rake h3:export` for YAML generation
- [ ] Build surge bucket infrastructure (Phase 5)

---

## 8. What This Preserves

- **5-tier pricing hierarchy**: Corridor > Inter-Zone > Zone-Time > Zone > City Default (unchanged)
- **Vehicle categories**: From `vehicle_categories.rb` (unchanged)
- **Inter-zone weighted average**: 60/40 origin/destination (unchanged)
- **Time bands**: morning/afternoon/evening in Asia/Kolkata (unchanged)
- **YAML config format**: Extended, not replaced
- **API response format**: Identical output
- **Redis 2-hour TTL**: Same pattern, better cache keys
- **`zones` table ownership**: Only ALTER TABLE, no structural changes

## 9. What This Replaces

- `Zone#contains_point_bbox?` -> `H3.from_geo_coordinates` + hash lookup
- O(n) linear zone scan -> O(1) constant-time lookup
- Rectangle boundaries -> Hexagonal tiles (no gaps, no overlaps)
- Ambiguous zone assignment -> Deterministic hex-to-zone mapping
