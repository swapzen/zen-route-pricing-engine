#!/usr/bin/env ruby
# =============================================================================
# FILL ZONE GAPS FOR HYDERABAD
# =============================================================================
# Generates new zone definitions for all uncovered areas visible in the zone map.
# Uses H3 R7 polyfill to create cells, removes cells already assigned to existing
# zones, and appends new zones to h3_zones.yml with city-default pricing.
#
# Usage:
#   RAILS_ENV=development bundle exec ruby script/fill_zone_gaps.rb
#
# What it does:
#   1. Reads current h3_zones.yml to get all existing R7 cells
#   2. Defines ~25 new zones for uncovered areas
#   3. Generates H3 R7 cells for each via bbox polyfill
#   4. Removes already-claimed cells (no overlaps)
#   5. Appends new zones to h3_zones.yml with city-default pricing
#   6. Prints summary of zones added and cells assigned
# =============================================================================

require_relative '../config/environment'
require 'yaml'
require 'h3'

YAML_PATH = Rails.root.join('config', 'zones', 'hyderabad', 'h3_zones.yml')
DEFAULTS_PATH = Rails.root.join('config', 'zones', 'hyderabad', 'vehicle_defaults.yml')

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Load existing zones and collect all claimed R7 cells
# ─────────────────────────────────────────────────────────────────────────────
puts "=" * 70
puts "HYDERABAD ZONE GAP FILLER"
puts "=" * 70

h3_config = YAML.load_file(YAML_PATH)
defaults_config = YAML.load_file(DEFAULTS_PATH)

existing_zones = h3_config['zones'] || {}
existing_r7_cells = Set.new

existing_zones.each do |zone_code, zone_data|
  cells = zone_data['h3_cells_r7'] || []
  cells.each { |c| existing_r7_cells.add(c) }
end

puts "\nExisting zones: #{existing_zones.size}"
puts "Existing R7 cells: #{existing_r7_cells.size}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Define new zones for all gap areas identified from map screenshots
# ─────────────────────────────────────────────────────────────────────────────
# Each zone defined with:
#   - center lat/lng (real-world landmark)
#   - bbox for H3 polyfill
#   - zone_type based on actual area character
#
# GAP AREAS identified from screenshots:
#   Northeast: Nagaram, Cheeryal, Yadgarpalle, Narsampalle, Pedda Amberpet (NE)
#   East: Vanasthalipuram outskirts, Peerzadiguda, Mansoorabad
#   Southeast: Pocharam, Turkayamjal, Kundoor, Kawadipally, Koheda
#   South: Meerpet outskirts, Balapur outskirts, Shaheen Nagar south, Mallapur
#   Southwest: Velmala, Kondakal, Mokila, Chevella Road
#   West: BHEL outskirts, Isnapur
#   Northwest: North Patancheru, Ameenpur outskirts, Sangareddy approach
#   Far North: Gagilapur, Amsaram, Sambhupur, Velgonda
# ─────────────────────────────────────────────────────────────────────────────

NEW_ZONES = {
  # ── NORTHEAST GAPS ──
  nagaram: {
    name: "Nagaram",
    zone_type: "residential_growth",
    center: [17.465, 78.565],
    bbox: { lat_min: 17.44, lat_max: 17.49, lng_min: 78.54, lng_max: 78.59 }
  },
  cheeryal: {
    name: "Cheeryal",
    zone_type: "residential_growth",
    center: [17.485, 78.545],
    bbox: { lat_min: 17.47, lat_max: 17.52, lng_min: 78.51, lng_max: 78.57 }
  },
  yadgarpalle: {
    name: "Yadgarpalle",
    zone_type: "residential_growth",
    center: [17.50, 78.525],
    bbox: { lat_min: 17.49, lat_max: 17.54, lng_min: 78.50, lng_max: 78.56 }
  },
  dammaiguda: {
    name: "Dammaiguda",
    zone_type: "residential_mixed",
    center: [17.455, 78.535],
    bbox: { lat_min: 17.43, lat_max: 17.47, lng_min: 78.51, lng_max: 78.56 }
  },
  rampally: {
    name: "Rampally",
    zone_type: "residential_growth",
    center: [17.445, 78.595],
    bbox: { lat_min: 17.42, lat_max: 17.47, lng_min: 78.57, lng_max: 78.62 }
  },

  # ── EAST GAPS ──
  peerzadiguda: {
    name: "Peerzadiguda",
    zone_type: "residential_dense",
    center: [17.415, 78.545],
    bbox: { lat_min: 17.39, lat_max: 17.44, lng_min: 78.52, lng_max: 78.57 }
  },
  vanasthalipuram: {
    name: "Vanasthalipuram",
    zone_type: "residential_dense",
    center: [17.335, 78.535],
    bbox: { lat_min: 17.31, lat_max: 17.37, lng_min: 78.51, lng_max: 78.57 }
  },
  mansoorabad: {
    name: "Mansoorabad",
    zone_type: "residential_mixed",
    center: [17.345, 78.555],
    bbox: { lat_min: 17.32, lat_max: 17.37, lng_min: 78.53, lng_max: 78.59 }
  },

  # ── SOUTHEAST GAPS ──
  pocharam_industrial: {
    name: "Pocharam Industrial Area",
    zone_type: "industrial",
    center: [17.42, 78.58],
    bbox: { lat_min: 17.39, lat_max: 17.45, lng_min: 78.56, lng_max: 78.62 }
  },
  turkayamjal: {
    name: "Turkayamjal",
    zone_type: "residential_growth",
    center: [17.28, 78.55],
    bbox: { lat_min: 17.25, lat_max: 17.31, lng_min: 78.52, lng_max: 78.58 }
  },
  kundoor: {
    name: "Kundoor",
    zone_type: "residential_growth",
    center: [17.32, 78.58],
    bbox: { lat_min: 17.30, lat_max: 17.35, lng_min: 78.56, lng_max: 78.62 }
  },
  kawadipally: {
    name: "Kawadipally",
    zone_type: "residential_growth",
    center: [17.30, 78.60],
    bbox: { lat_min: 17.27, lat_max: 17.33, lng_min: 78.58, lng_max: 78.64 }
  },
  koheda: {
    name: "Koheda",
    zone_type: "residential_growth",
    center: [17.26, 78.53],
    bbox: { lat_min: 17.23, lat_max: 17.28, lng_min: 78.50, lng_max: 78.56 }
  },
  pedda_amberpet: {
    name: "Pedda Amberpet",
    zone_type: "residential_growth",
    center: [17.30, 78.64],
    bbox: { lat_min: 17.27, lat_max: 17.34, lng_min: 78.62, lng_max: 78.68 }
  },

  # ── SOUTH GAPS ──
  meerpet: {
    name: "Meerpet",
    zone_type: "residential_dense",
    center: [17.325, 78.50],
    bbox: { lat_min: 17.30, lat_max: 17.35, lng_min: 78.48, lng_max: 78.53 }
  },
  balapur: {
    name: "Balapur",
    zone_type: "residential_mixed",
    center: [17.315, 78.48],
    bbox: { lat_min: 17.29, lat_max: 17.34, lng_min: 78.45, lng_max: 78.50 }
  },
  shaheen_nagar: {
    name: "Shaheen Nagar",
    zone_type: "residential_dense",
    center: [17.345, 78.465],
    bbox: { lat_min: 17.32, lat_max: 17.37, lng_min: 78.44, lng_max: 78.49 }
  },
  mallapur_south: {
    name: "Mallapur South",
    zone_type: "residential_mixed",
    center: [17.33, 78.44],
    bbox: { lat_min: 17.30, lat_max: 17.36, lng_min: 78.41, lng_max: 78.47 }
  },

  # ── SOUTHWEST GAPS ──
  velmala: {
    name: "Velmala",
    zone_type: "residential_growth",
    center: [17.42, 78.30],
    bbox: { lat_min: 17.39, lat_max: 17.45, lng_min: 78.27, lng_max: 78.33 }
  },
  kondakal: {
    name: "Kondakal",
    zone_type: "residential_growth",
    center: [17.40, 78.32],
    bbox: { lat_min: 17.37, lat_max: 17.42, lng_min: 78.29, lng_max: 78.35 }
  },
  mokila: {
    name: "Mokila",
    zone_type: "residential_growth",
    center: [17.38, 78.28],
    bbox: { lat_min: 17.35, lat_max: 17.41, lng_min: 78.25, lng_max: 78.31 }
  },
  chevella_road: {
    name: "Chevella Road",
    zone_type: "outer_ring",
    center: [17.36, 78.30],
    bbox: { lat_min: 17.33, lat_max: 17.38, lng_min: 78.26, lng_max: 78.32 }
  },

  # ── WEST / NORTHWEST GAPS ──
  isnapur: {
    name: "Isnapur",
    zone_type: "residential_growth",
    center: [17.48, 78.28],
    bbox: { lat_min: 17.46, lat_max: 17.51, lng_min: 78.25, lng_max: 78.31 }
  },
  sangareddy_approach: {
    name: "Sangareddy Approach",
    zone_type: "outer_ring",
    center: [17.50, 78.25],
    bbox: { lat_min: 17.48, lat_max: 17.53, lng_min: 78.22, lng_max: 78.28 }
  },

  # ── FAR NORTH GAPS ──
  gagilapur: {
    name: "Gagilapur",
    zone_type: "residential_growth",
    center: [17.56, 78.42],
    bbox: { lat_min: 17.53, lat_max: 17.59, lng_min: 78.39, lng_max: 78.45 }
  },
  sambhupur: {
    name: "Sambhupur",
    zone_type: "residential_growth",
    center: [17.57, 78.48],
    bbox: { lat_min: 17.54, lat_max: 17.60, lng_min: 78.45, lng_max: 78.51 }
  },
  velgonda: {
    name: "Velgonda",
    zone_type: "outer_ring",
    center: [17.55, 78.35],
    bbox: { lat_min: 17.52, lat_max: 17.58, lng_min: 78.32, lng_max: 78.38 }
  },

  # ── ADDITIONAL SUBURBAN GAPS (visible as white areas in maps) ──
  yamnampet: {
    name: "Yamnampet",
    zone_type: "residential_growth",
    center: [17.44, 78.62],
    bbox: { lat_min: 17.42, lat_max: 17.47, lng_min: 78.60, lng_max: 78.66 }
  },
  nagarjuna_sagar_road: {
    name: "Nagarjuna Sagar Road",
    zone_type: "residential_growth",
    center: [17.28, 78.48],
    bbox: { lat_min: 17.25, lat_max: 17.31, lng_min: 78.45, lng_max: 78.51 }
  },
  manneguda: {
    name: "Manneguda",
    zone_type: "residential_growth",
    center: [17.27, 78.42],
    bbox: { lat_min: 17.24, lat_max: 17.30, lng_min: 78.39, lng_max: 78.45 }
  },
  gollapalle: {
    name: "Gollapalle",
    zone_type: "outer_ring",
    center: [17.35, 78.38],
    bbox: { lat_min: 17.32, lat_max: 17.38, lng_min: 78.35, lng_max: 78.41 }
  },
  moulkupalle: {
    name: "Moulkupalle",
    zone_type: "outer_ring",
    center: [17.38, 78.33],
    bbox: { lat_min: 17.35, lat_max: 17.40, lng_min: 78.30, lng_max: 78.36 }
  },
  nagapally: {
    name: "Nagapally",
    zone_type: "residential_growth",
    center: [17.25, 78.58],
    bbox: { lat_min: 17.22, lat_max: 17.28, lng_min: 78.55, lng_max: 78.61 }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Generate H3 R7 cells for each new zone
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{'─' * 70}"
puts "Generating H3 R7 cells for #{NEW_ZONES.size} new zones..."
puts '─' * 70

new_zones_data = {}
total_new_cells = 0
all_new_cells = Set.new

NEW_ZONES.each do |zone_code, zone_def|
  bbox = zone_def[:bbox]

  # Create polygon for H3 polyfill (counter-clockwise for H3)
  polygon = [[
    [bbox[:lat_min], bbox[:lng_min]],
    [bbox[:lat_min], bbox[:lng_max]],
    [bbox[:lat_max], bbox[:lng_max]],
    [bbox[:lat_max], bbox[:lng_min]]
  ]]

  # Get all R7 cells covering this bbox
  begin
    h3_ints = H3.polyfill(polygon, 7)
  rescue => e
    puts "  WARNING: H3.polyfill failed for #{zone_code}: #{e.message}"
    # Fallback: use center + k_ring
    center_h3 = H3.from_geo_coordinates(zone_def[:center], 7)
    h3_ints = H3.k_ring(center_h3, 2)
  end

  # Also add corner and center cells to ensure coverage
  corners = [
    [bbox[:lat_min], bbox[:lng_min]],
    [bbox[:lat_min], bbox[:lng_max]],
    [bbox[:lat_max], bbox[:lng_min]],
    [bbox[:lat_max], bbox[:lng_max]],
    zone_def[:center]
  ]
  corners.each do |lat, lng|
    h3_int = H3.from_geo_coordinates([lat, lng], 7)
    h3_ints << h3_int unless h3_ints.include?(h3_int)
  end

  # Convert to hex strings
  hex_cells = h3_ints.map { |h3_int| h3_int.to_s(16) }

  # Remove cells already claimed by existing zones
  unclaimed = hex_cells.reject { |c| existing_r7_cells.include?(c) }

  # Remove cells already claimed by other new zones in this batch
  unclaimed = unclaimed.reject { |c| all_new_cells.include?(c) }

  if unclaimed.empty?
    puts "  SKIP: #{zone_code} — all cells already claimed"
    next
  end

  # Claim these cells
  unclaimed.each { |c| all_new_cells.add(c) }

  new_zones_data[zone_code.to_s] = {
    cells: unclaimed.sort,
    name: zone_def[:name],
    zone_type: zone_def[:zone_type],
    center: zone_def[:center]
  }

  total_new_cells += unclaimed.size
  puts "  #{zone_code}: #{unclaimed.size} cells (#{hex_cells.size} total, #{hex_cells.size - unclaimed.size} already claimed)"
end

puts "\nNew zones to add: #{new_zones_data.size}"
puts "New R7 cells: #{total_new_cells}"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Build pricing from city defaults (global_time_rates)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{'─' * 70}"
puts "Building pricing from vehicle_defaults.yml global_time_rates..."
puts '─' * 70

global_rates = defaults_config['global_time_rates']
time_bands = %w[early_morning morning_rush midday afternoon evening_rush night weekend_day weekend_night]
vehicles = %w[two_wheeler scooter mini_3w three_wheeler three_wheeler_ev tata_ace pickup_8ft eeco tata_407 canter_14ft]

# Outer-ring / growth zones get a small discount (5% less) to attract demand
ZONE_TYPE_RATE_ADJUSTMENTS = {
  'outer_ring' => 0.93,
  'residential_growth' => 0.97,
  'residential_dense' => 1.0,
  'residential_mixed' => 0.98,
  'industrial' => 0.95,
  'default' => 1.0
}

def build_pricing_for_zone(global_rates, time_bands, vehicles, zone_type, adjustments)
  adj = adjustments[zone_type] || 1.0
  pricing = {}

  time_bands.each do |band|
    band_rates = global_rates[band]
    next unless band_rates

    pricing[band] = {}
    vehicles.each do |vehicle|
      vr = band_rates[vehicle]
      next unless vr

      pricing[band][vehicle] = {
        'base' => (vr['base'] * adj).round,
        'rate' => (vr['rate'] * adj).round
      }
    end
  end

  pricing
end

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Append new zones to h3_zones.yml
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{'─' * 70}"
puts "Appending #{new_zones_data.size} new zones to h3_zones.yml..."
puts '─' * 70

# Priority assignments by zone_type
ZONE_TYPE_PRIORITIES = {
  'tech_corridor' => 20,
  'business_cbd' => 18,
  'airport_logistics' => 16,
  'residential_growth' => 10,
  'residential_dense' => 14,
  'residential_mixed' => 12,
  'traditional_commercial' => 15,
  'premium_residential' => 19,
  'industrial' => 12,
  'heritage_commercial' => 15,
  'outer_ring' => 8,
  'default' => 5
}

# Build the YAML entries
new_yaml_zones = {}

new_zones_data.each do |zone_code, data|
  pricing = build_pricing_for_zone(
    global_rates, time_bands, vehicles,
    data[:zone_type], ZONE_TYPE_RATE_ADJUSTMENTS
  )

  new_yaml_zones[zone_code] = {
    'name' => data[:name],
    'zone_type' => data[:zone_type],
    'priority' => ZONE_TYPE_PRIORITIES[data[:zone_type]] || 10,
    'active' => true,
    'auto_generated' => false,
    'h3_cells_r7' => data[:cells],
    'pricing' => pricing
  }
end

# Read the full YAML, add new zones, write back
h3_config['zones'].merge!(new_yaml_zones)
h3_config['generated_at'] = Time.current.iso8601
h3_config['version'] = '2.1'

File.write(YAML_PATH, h3_config.to_yaml)

puts "Written #{new_yaml_zones.size} new zones to h3_zones.yml"
puts "Total zones now: #{h3_config['zones'].size}"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
puts "\n#{'=' * 70}"
puts "SUMMARY"
puts '=' * 70
puts "Previous zones: #{existing_zones.size}"
puts "New zones added: #{new_yaml_zones.size}"
puts "Total zones now: #{h3_config['zones'].size}"
puts "Previous R7 cells: #{existing_r7_cells.size}"
puts "New R7 cells: #{total_new_cells}"
puts "Total R7 cells: #{existing_r7_cells.size + total_new_cells}"
puts ""
puts "New zones by type:"
type_counts = new_yaml_zones.values.group_by { |z| z['zone_type'] }.transform_values(&:size)
type_counts.sort_by { |_, v| -v }.each { |t, c| puts "  #{t}: #{c}" }
puts ""
puts "Next steps:"
puts "  1. Review the changes in h3_zones.yml"
puts "  2. Run: rails zones:h3_sync[hyd]"
puts "  3. Verify in admin dashboard zone map"
puts '=' * 70
