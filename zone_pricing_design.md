# Zone-Aware Pricing Engine v4.5 Design & Integration Guide

## 1. Schema & CockroachDB Strategy

### Tables
- **`zones`**: Enhanced with `zone_code`, `zone_type`, `lat/lng` bounds. 
  - *CockroachDB*: Primary Key mapped to UUID or BigInt. `city_code` is a key column for partitioning.
  - *Index*: `[:city, :zone_code]` (Unique) allows efficient city-scoped lookups.
- **`zone_vehicle_pricings`**: Stores base fare, min fare, base distance, and per-km rate overrides per vehicle per zone.
  - *Index*: `[:city_code, :zone_id, :vehicle_type]` (Unique) ensures O(1) lookup during price calculation.
- **`zone_pair_vehicle_pricings`**: Stores corridor-specific pricing (e.g. Gachibowli -> Ameerpet).
  - *Index*: `[:city_code, :from_zone_id, :to_zone_id, :vehicle_type]` (Unique) is critical for route resolution.

### Partitioning Strategy
For massive scale (multi-city), we recommend **List Partitioning** by `city_code`.
```sql
ALTER TABLE zones PARTITION BY LIST (city_code) ...
```
This keeps all Hyderabad data on Hyderabad nodes (if geo-partitioned) or simply grouped together for cache locality.

## 2. Integration Flow

### 2.1 Base Pricing Resolution Priority (ZonePricingResolver)

Base pricing is resolved in a single place `ZonePricingResolver`, with this priority:

1.  **Corridor Override**
    Look up `zone_pair_vehicle_pricings` for `(city_code, from_zone_id, to_zone_id, vehicle_type, active: true)`.
2.  **Intra-zone Override**
    If `pickup_zone_id == drop_zone_id`, use `zone_vehicle_pricings` for that `(city_code, zone_id, vehicle_type)`.
3.  **Origin-zone Override**
    Else, use `zone_vehicle_pricings` for the `pickup_zone` if present.
4.  **(Future) Zone-type Structural Multipliers**
    If no explicit zone config exists, we may apply `zone_type` multipliers on top of city defaults (e.g. `tech_corridor` +10% for trucks).
5.  **City Default**
    Fall back to `pricing_configs` and `pricing_distance_slabs` for that `(city_code, vehicle_type)`.

The resolver returns a result struct (e.g. `OpenStruct` or `Result` object):

```ruby
OpenStruct.new(
  base_fare_paise: ...,
  min_fare_paise: ...,
  base_distance_m: ...,
  per_km_rate_paise: ...,
  pricing_mode: :linear, # or :slab
  source: :corridor_override # or :zone_override / :zone_type / :city_default
)
```

**Pricing Modes:**
*   **`:linear`** (Default for Zone/Corridor overrides):
    `Price = base_fare + (per_km_rate * distance_km)`, min-clamped by `min_fare`.
*   **`:slab`** (Default for City-level):
    Use `pricing_distance_slabs` logic (as in v2.9/v3.0).

### 2.2 Dynamic Layers (Applied after Zone-Aware Base)

1.  **Traffic Multiplier**:
    Derived from Google Maps `duration_in_traffic_s`.
2.  **Time-of-Day Multiplier** (from v3.0):
    *   3 Bands: Morning (06-12), Afternoon (12-18), Evening/Night (18-06).
    *   Vehicle Groups: Small, Mid, Heavy.
3.  **Zone-Demand Multiplier**:
    For hotspots (short-term demand/supply).

> **Note**: In `calibration_mode` (`ENV['PRICING_MODE'] == 'calibration'`), all dynamic multipliers are forced to `1.0`. Only structural base differences (Zone vs City) are visible compared to Porter.

### 2.3 Logging & Unit Economics Hooks

**Logging Strategy**
For each quote, we must log:
*   `city_code`, `vehicle_type`
*   `pickup_zone_code`, `drop_zone_code`
*   `pricing_source` (:corridor / :zone / :city_default)
*   `time_band`
*   `final_multipliers` (traffic, time, zone)

**Unit Economics**
After computing `price_after_margin`, we will add a hook:
*   `CostModel.cost_floor`: Ensure we never price below cost (fuel + driver + maintenance + platform overhead).

## 3. Future Multi-Zone Path (Step 4)

We introduced `RouteZoneSegmenter` interface.
Future implementation:
1.  Decode Google Polyline.
2.  Use PostGIS/CockroachDB `ST_Intersection` to split route into weighted segments.
    - `Segment(zone=Tech, distance=3km, rate=₹20/km)`
    - `Segment(zone=Residential, distance=5km, rate=₹15/km)`
3.  Sum up the cost: `Σ(seg.distance * seg.rate)`.

## 4. Usage Example

```ruby
resolver = RoutePricing::Services::ZonePricingResolver.new
price = resolver.resolve(
  city_code: 'hyd', 
  vehicle_type: 'tata_ace',
  pickup_lat: 17.44, pickup_lng: 78.38, # Tech Corridor
  drop_lat: 17.36, drop_lng: 78.47      # Old City
)

# Returns struct with specific base rates for Tech -> Old City if defined,
# or Tech Corridor base rates if generic.
```
