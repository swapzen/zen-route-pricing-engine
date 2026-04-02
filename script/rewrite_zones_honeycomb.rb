#!/usr/bin/env ruby
# =============================================================================
# HYDERABAD ZONE REWRITE — HONEYCOMB APPROACH
# =============================================================================
#
# Uses H3 Honeycomb Conjecture to guarantee ZERO GAPS, ZERO OVERLAPS.
#
# Algorithm:
#   1. Define Hyderabad metro boundary (GHMC + HMDA suburban)
#   2. H3.polyfill(boundary, R7) → generate ALL R7 cells (~500-700)
#   3. Define ~110 zone centers (real-world landmarks, GHMC-aligned)
#   4. For each R7 cell → find nearest zone center → assign (Voronoi)
#   5. Apply pricing (city defaults × zone_type × tier adjustments)
#   6. Write fresh h3_zones.yml (complete rewrite)
#
# Guarantees (by Honeycomb Conjecture / H3 properties):
#   - Every point inside boundary maps to exactly one R7 cell (O(1))
#   - Every R7 cell is assigned to exactly one zone
#   - No gaps, no overlaps, no fallbacks needed
#
# Usage:
#   RAILS_ENV=development bundle exec ruby script/rewrite_zones_honeycomb.rb
#
# Options:
#   DRY_RUN=true   — preview only, don't write YAML
#   VERBOSE=true   — print cell assignments
# =============================================================================

require_relative '../config/environment'
require 'yaml'
require 'h3'

DRY_RUN = ENV['DRY_RUN'] == 'true'
VERBOSE = ENV['VERBOSE'] == 'true'

YAML_PATH = Rails.root.join('config', 'zones', 'hyderabad', 'h3_zones.yml')
DEFAULTS_PATH = Rails.root.join('config', 'zones', 'hyderabad', 'vehicle_defaults.yml')
BACKUP_PATH = Rails.root.join('config', 'zones', 'hyderabad', "h3_zones_backup_#{Time.current.strftime('%Y%m%d_%H%M%S')}.yml")

puts "=" * 80
puts "HYDERABAD ZONE REWRITE — HONEYCOMB APPROACH"
puts "=" * 80
puts "Mode: #{DRY_RUN ? 'DRY RUN (preview only)' : 'LIVE (will write YAML)'}"
puts ""

# =============================================================================
# STEP 1: DEFINE HYDERABAD METRO BOUNDARY
# =============================================================================
# Covers full HMDA serviceable area:
#   North:  17.66°N (Medchal, Shamirpet, Dundigal)
#   South:  17.15°N (Beyond Shamshabad airport, Ibrahimpatnam outskirts)
#   East:   78.75°E (Beyond Ghatkesar, Pocharam)
#   West:   78.18°E (Beyond Patancheru, Sangareddy approach)
# Total: ~2800 km² covering entire metro delivery area
# =============================================================================

BOUNDARY = {
  lat_min: 17.15,
  lat_max: 17.66,
  lng_min: 78.18,
  lng_max: 78.75
}

BOUNDARY_POLYGON = [[
  [BOUNDARY[:lat_min], BOUNDARY[:lng_min]],
  [BOUNDARY[:lat_min], BOUNDARY[:lng_max]],
  [BOUNDARY[:lat_max], BOUNDARY[:lng_max]],
  [BOUNDARY[:lat_max], BOUNDARY[:lng_min]]
]]

puts "Step 1: Metro boundary defined"
puts "  #{BOUNDARY[:lat_min]}°N to #{BOUNDARY[:lat_max]}°N (#{((BOUNDARY[:lat_max] - BOUNDARY[:lat_min]) * 111).round}km N-S)"
puts "  #{BOUNDARY[:lng_min]}°E to #{BOUNDARY[:lng_max]}°E (#{((BOUNDARY[:lng_max] - BOUNDARY[:lng_min]) * 111 * Math.cos(17.4 * Math::PI / 180)).round}km E-W)"

# =============================================================================
# STEP 2: GENERATE ALL R7 CELLS (Honeycomb grid)
# =============================================================================

puts "\nStep 2: Generating H3 R7 honeycomb grid..."

all_r7_ints = H3.polyfill(BOUNDARY_POLYGON, 7)

# Also add cells for boundary corners and edges (polyfill can miss edges)
edge_points = []
lat_step = 0.02
lng_step = 0.02
lat = BOUNDARY[:lat_min]
while lat <= BOUNDARY[:lat_max]
  lng = BOUNDARY[:lng_min]
  while lng <= BOUNDARY[:lng_max]
    edge_points << [lat, lng]
    lng += lng_step
  end
  lat += lat_step
end

edge_points.each do |lat, lng|
  h3_int = H3.from_geo_coordinates([lat, lng], 7)
  all_r7_ints << h3_int unless all_r7_ints.include?(h3_int)
end

# Convert to hex strings and compute centers
all_r7_cells = {}
all_r7_ints.uniq.each do |h3_int|
  hex = h3_int.to_s(16)
  lat, lng = H3.to_geo_coordinates(h3_int)
  all_r7_cells[hex] = { lat: lat, lng: lng, h3_int: h3_int }
end

puts "  Total R7 cells: #{all_r7_cells.size}"
puts "  Coverage: ~#{(all_r7_cells.size * 5.16).round} km²"

# =============================================================================
# STEP 3: DEFINE ZONE CENTERS (~110 zones)
# =============================================================================
# Organized by GHMC's 6 administrative zones + 4 beyond-GHMC regions.
# Each center is a real-world landmark with approximate coordinates.
# The Voronoi assignment makes exact placement non-critical — even 500m
# offset just shifts the boundary slightly.
#
# Zone types:
#   tech_corridor, business_cbd, airport_logistics, residential_growth,
#   residential_dense, residential_mixed, traditional_commercial,
#   premium_residential, industrial, heritage_commercial, outer_ring
#
# Tiers:
#   core    — inside ORR (higher pricing)
#   fringe  — ORR belt / GHMC edge (standard pricing)
#   suburb  — beyond GHMC, HMDA (discounted pricing)
#   outer   — far HMDA edge (deep discount)
# =============================================================================

puts "\nStep 3: Defining zone centers..."

ZONE_CENTERS = {
  # ═══════════════════════════════════════════════════════════════════════════
  # GHMC ZONE 1: CHARMINAR (Old City / South Core)
  # ═══════════════════════════════════════════════════════════════════════════
  old_city_charminar: {
    name: "Old City / Charminar / Yakutpura", lat: 17.3580, lng: 78.4680,
    zone_type: "traditional_commercial", tier: "core"
  },
  falaknuma_chandrayangutta: {
    name: "Falaknuma / Chandrayangutta / Shaheen Nagar", lat: 17.3380, lng: 78.4550,
    zone_type: "heritage_commercial", tier: "core"
  },
  meerpet_santoshnagar: {
    name: "Meerpet / Santosh Nagar / Saidabad / Champapet", lat: 17.3450, lng: 78.4980,
    zone_type: "residential_dense", tier: "core"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # GHMC ZONE 2: KHAIRATABAD (Central / Premium)
  # ═══════════════════════════════════════════════════════════════════════════
  banjara_jubilee: {
    name: "Banjara Hills / Jubilee Hills / Film Nagar", lat: 17.4230, lng: 78.4200,
    zone_type: "premium_residential", tier: "core"
  },
  ameerpet_begumpet: {
    name: "Ameerpet / Begumpet / SR Nagar / Somajiguda", lat: 17.4430, lng: 78.4550,
    zone_type: "business_cbd", tier: "core"
  },
  cbd_central: {
    name: "Nampally / Abids / Masab Tank / Khairatabad", lat: 17.3960, lng: 78.4620,
    zone_type: "business_cbd", tier: "core"
  },
  mehdipatnam: {
    name: "Mehdipatnam / Shaikpet", lat: 17.3960, lng: 78.4280,
    zone_type: "residential_mixed", tier: "core"
  },
  golconda: {
    name: "Golconda / Tolichowki", lat: 17.3880, lng: 78.4050,
    zone_type: "heritage_commercial", tier: "core"
  },
  rajendranagar_velmala: {
    name: "Rajendranagar / Velmala / Kismatpur", lat: 17.3600, lng: 78.3900,
    zone_type: "residential_growth", tier: "fringe"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # GHMC ZONE 3: KUKATPALLY (Northwest)
  # ═══════════════════════════════════════════════════════════════════════════
  kukatpally: {
    name: "Kukatpally / KPHB / Pragathi Nagar", lat: 17.4940, lng: 78.3920,
    zone_type: "residential_dense", tier: "core"
  },
  moosapet: {
    name: "Moosapet / Erragadda / Borabanda", lat: 17.4620, lng: 78.4250,
    zone_type: "residential_mixed", tier: "core"
  },
  jeedimetla_balanagar: {
    name: "Jeedimetla / Balanagar Industrial", lat: 17.4880, lng: 78.4400,
    zone_type: "industrial", tier: "core"
  },
  miyapur: {
    name: "Miyapur", lat: 17.4960, lng: 78.3550,
    zone_type: "residential_mixed", tier: "fringe"
  },
  bachupally: {
    name: "Bachupally", lat: 17.5350, lng: 78.3700,
    zone_type: "residential_growth", tier: "fringe"
  },
  nizampet: {
    name: "Nizampet / Pragathi Nagar", lat: 17.5150, lng: 78.3800,
    zone_type: "residential_growth", tier: "fringe"
  },
  gajularamaram: {
    name: "Gajularamaram", lat: 17.5020, lng: 78.4150,
    zone_type: "residential_mixed", tier: "fringe"
  },
  ameenpur_beeramguda: {
    name: "Ameenpur / Beeramguda", lat: 17.5170, lng: 78.3200,
    zone_type: "residential_growth", tier: "fringe"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # GHMC ZONE 4: LB NAGAR (Southeast)
  # ═══════════════════════════════════════════════════════════════════════════
  lb_nagar: {
    name: "LB Nagar / Saroornagar / Vanasthalipuram", lat: 17.3400, lng: 78.5400,
    zone_type: "residential_dense", tier: "core"
  },
  dilsukhnagar: {
    name: "Dilsukhnagar / Kothapet", lat: 17.3710, lng: 78.5200,
    zone_type: "residential_dense", tier: "core"
  },
  hayathnagar_kundoor: {
    name: "Hayathnagar / Kundoor", lat: 17.3250, lng: 78.5900,
    zone_type: "residential_growth", tier: "fringe"
  },
  uppal_nagole: {
    name: "Uppal / Nagole", lat: 17.3980, lng: 78.5550,
    zone_type: "residential_dense", tier: "core"
  },
  balapur: {
    name: "Balapur / Badangpet", lat: 17.3020, lng: 78.4750,
    zone_type: "residential_mixed", tier: "fringe"
  },
  mansoorabad: {
    name: "Mansoorabad", lat: 17.3350, lng: 78.5700,
    zone_type: "residential_growth", tier: "fringe"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # GHMC ZONE 5: SECUNDERABAD (North / Northeast)
  # ═══════════════════════════════════════════════════════════════════════════
  secunderabad: {
    name: "Secunderabad CBD / Kavadiguda", lat: 17.4380, lng: 78.4950,
    zone_type: "business_cbd", tier: "core"
  },
  malkajgiri_kapra: {
    name: "Malkajgiri / Marredpally / Kapra / Moula Ali", lat: 17.4600, lng: 78.5200,
    zone_type: "residential_dense", tier: "core"
  },
  tarnaka: {
    name: "Tarnaka / Nacharam", lat: 17.4320, lng: 78.5350,
    zone_type: "residential_mixed", tier: "core"
  },
  ecil: {
    name: "ECIL / AS Rao Nagar", lat: 17.4700, lng: 78.5650,
    zone_type: "residential_mixed", tier: "core"
  },
  amberpet_malakpet: {
    name: "Amberpet / Malakpet / Chaderghat", lat: 17.4000, lng: 78.5050,
    zone_type: "residential_mixed", tier: "core"
  },
  bowenpally: {
    name: "Bowenpally", lat: 17.4650, lng: 78.4800,
    zone_type: "residential_mixed", tier: "core"
  },
  alwal: {
    name: "Alwal / Bollaram", lat: 17.5050, lng: 78.5000,
    zone_type: "residential_mixed", tier: "fringe"
  },
  boduppal: {
    name: "Boduppal", lat: 17.4150, lng: 78.5800,
    zone_type: "residential_growth", tier: "fringe"
  },
  dammaiguda_peerzadiguda: {
    name: "Dammaiguda / Peerzadiguda", lat: 17.4450, lng: 78.5720,
    zone_type: "residential_growth", tier: "fringe"
  },
  sainikpuri_cheeryal: {
    name: "Sainikpuri / Cheeryal / CRPF", lat: 17.4920, lng: 78.5500,
    zone_type: "residential_growth", tier: "fringe"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # GHMC ZONE 6: SERILINGAMPALLY (West / IT Corridor)
  # ═══════════════════════════════════════════════════════════════════════════
  hitec_gachibowli: {
    name: "HITEC City / Gachibowli / Madhapur / Financial District", lat: 17.4400, lng: 78.3700,
    zone_type: "tech_corridor", tier: "core"
  },
  kondapur: {
    name: "Kondapur / Whitefields", lat: 17.4620, lng: 78.3500,
    zone_type: "tech_corridor", tier: "core"
  },
  manikonda: {
    name: "Manikonda / Puppalguda", lat: 17.4000, lng: 78.3830,
    zone_type: "residential_mixed", tier: "core"
  },
  narsingi: {
    name: "Narsingi / Kokapet", lat: 17.3900, lng: 78.3450,
    zone_type: "residential_growth", tier: "fringe"
  },
  tellapur: {
    name: "Tellapur", lat: 17.4800, lng: 78.3300,
    zone_type: "residential_growth", tier: "fringe"
  },
  gandipet: {
    name: "Gandipet / Osman Sagar", lat: 17.3750, lng: 78.3100,
    zone_type: "residential_growth", tier: "fringe"
  },
  bandlaguda: {
    name: "Bandlaguda Jagir", lat: 17.3580, lng: 78.3450,
    zone_type: "residential_growth", tier: "fringe"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — NORTH (Medchal-Malkajgiri District)
  # ═══════════════════════════════════════════════════════════════════════════
  kompally: {
    name: "Kompally", lat: 17.5350, lng: 78.4850,
    zone_type: "residential_growth", tier: "suburb"
  },
  medchal: {
    name: "Medchal", lat: 17.6300, lng: 78.4800,
    zone_type: "residential_growth", tier: "outer"
  },
  shamirpet: {
    name: "Shamirpet", lat: 17.5900, lng: 78.5400,
    zone_type: "outer_ring", tier: "outer"
  },
  dundigal: {
    name: "Dundigal", lat: 17.5700, lng: 78.4100,
    zone_type: "residential_growth", tier: "suburb"
  },
  gagilapur_kandlakoya: {
    name: "Gagilapur / Kandlakoya", lat: 17.5550, lng: 78.4550,
    zone_type: "residential_growth", tier: "suburb"
  },
  mallampet: {
    name: "Mallampet", lat: 17.5400, lng: 78.4300,
    zone_type: "residential_growth", tier: "suburb"
  },
  velgonda: {
    name: "Velgonda", lat: 17.5800, lng: 78.3600,
    zone_type: "outer_ring", tier: "outer"
  },
  sambhupur: {
    name: "Sambhupur / Gundla Pochampally", lat: 17.5700, lng: 78.5000,
    zone_type: "outer_ring", tier: "outer"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — NORTHEAST (Keesara belt)
  # ═══════════════════════════════════════════════════════════════════════════
  keesara: {
    name: "Keesara", lat: 17.5200, lng: 78.5700,
    zone_type: "residential_growth", tier: "suburb"
  },
  nagaram: {
    name: "Nagaram", lat: 17.4700, lng: 78.5900,
    zone_type: "residential_growth", tier: "suburb"
  },
  rampally: {
    name: "Rampally", lat: 17.4500, lng: 78.6200,
    zone_type: "residential_growth", tier: "suburb"
  },
  yadgarpalle: {
    name: "Yadgarpalle", lat: 17.5100, lng: 78.5300,
    zone_type: "residential_growth", tier: "suburb"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — EAST (Ghatkesar, Pocharam belt)
  # ═══════════════════════════════════════════════════════════════════════════
  ghatkesar: {
    name: "Ghatkesar", lat: 17.4500, lng: 78.6500,
    zone_type: "residential_growth", tier: "suburb"
  },
  pocharam: {
    name: "Pocharam SEZ", lat: 17.4350, lng: 78.6200,
    zone_type: "industrial", tier: "suburb"
  },
  yamnampet: {
    name: "Yamnampet", lat: 17.4250, lng: 78.6400,
    zone_type: "residential_growth", tier: "suburb"
  },
  pedda_amberpet: {
    name: "Pedda Amberpet", lat: 17.3900, lng: 78.6400,
    zone_type: "residential_growth", tier: "outer"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — SOUTHEAST
  # ═══════════════════════════════════════════════════════════════════════════
  ibrahimpatnam: {
    name: "Ibrahimpatnam", lat: 17.2700, lng: 78.5600,
    zone_type: "residential_growth", tier: "outer"
  },
  turkayamjal: {
    name: "Turkayamjal", lat: 17.2900, lng: 78.5300,
    zone_type: "residential_growth", tier: "outer"
  },
  kawadipally: {
    name: "Kawadipally", lat: 17.3000, lng: 78.6200,
    zone_type: "outer_ring", tier: "outer"
  },
  nagapally: {
    name: "Nagapally", lat: 17.2500, lng: 78.5900,
    zone_type: "outer_ring", tier: "outer"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — SOUTH (Airport / Shamshabad belt)
  # ═══════════════════════════════════════════════════════════════════════════
  shamshabad: {
    name: "Shamshabad / RGIA Airport", lat: 17.2400, lng: 78.4300,
    zone_type: "airport_logistics", tier: "suburb"
  },
  adibatla: {
    name: "Adibatla Aerospace", lat: 17.2600, lng: 78.4900,
    zone_type: "industrial", tier: "suburb"
  },
  jalpally: {
    name: "Jalpally", lat: 17.3100, lng: 78.4350,
    zone_type: "residential_growth", tier: "fringe"
  },
  manneguda: {
    name: "Manneguda", lat: 17.2700, lng: 78.4300,
    zone_type: "residential_growth", tier: "outer"
  },
  nagarjuna_sagar_road: {
    name: "Nagarjuna Sagar Road", lat: 17.2800, lng: 78.4700,
    zone_type: "residential_growth", tier: "outer"
  },
  maheshwaram: {
    name: "Maheshwaram", lat: 17.2100, lng: 78.4500,
    zone_type: "outer_ring", tier: "outer"
  },
  koheda: {
    name: "Koheda", lat: 17.2500, lng: 78.5200,
    zone_type: "outer_ring", tier: "outer"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — SOUTHWEST (Mokila, Chevella belt)
  # ═══════════════════════════════════════════════════════════════════════════
  mokila: {
    name: "Mokila", lat: 17.3850, lng: 78.2750,
    zone_type: "residential_growth", tier: "suburb"
  },
  shankarpally: {
    name: "Shankarpally", lat: 17.3600, lng: 78.2400,
    zone_type: "outer_ring", tier: "outer"
  },
  chevella_road: {
    name: "Chevella Road / Moulkupalle", lat: 17.3500, lng: 78.2800,
    zone_type: "outer_ring", tier: "outer"
  },
  kondakal: {
    name: "Kondakal", lat: 17.4000, lng: 78.3200,
    zone_type: "residential_growth", tier: "suburb"
  },
  gollapalle: {
    name: "Gollapalle", lat: 17.3350, lng: 78.3800,
    zone_type: "outer_ring", tier: "suburb"
  },
  mallapur_south: {
    name: "Mallapur South / Langar Houz / Attapur", lat: 17.3550, lng: 78.4350,
    zone_type: "residential_mixed", tier: "fringe"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # BEYOND GHMC — WEST / NORTHWEST
  # ═══════════════════════════════════════════════════════════════════════════
  patancheru: {
    name: "Patancheru", lat: 17.5300, lng: 78.2700,
    zone_type: "industrial", tier: "suburb"
  },
  isnapur: {
    name: "Isnapur / RC Puram / Ramachandrapuram", lat: 17.5100, lng: 78.3050,
    zone_type: "residential_growth", tier: "suburb"
  },
  sangareddy_approach: {
    name: "Sangareddy Approach", lat: 17.5500, lng: 78.2400,
    zone_type: "outer_ring", tier: "outer"
  },

  # ═══════════════════════════════════════════════════════════════════════════
  # FAR CORNERS (catch-all large zones)
  # ═══════════════════════════════════════════════════════════════════════════
  far_north: {
    name: "Far North / Pregnapur", lat: 17.6400, lng: 78.4300,
    zone_type: "outer_ring", tier: "outer"
  },
  far_northeast: {
    name: "Far Northeast / Korremula", lat: 17.5500, lng: 78.5800,
    zone_type: "outer_ring", tier: "outer"
  },
  far_east: {
    name: "Far East / Bhongir Approach", lat: 17.4600, lng: 78.7000,
    zone_type: "outer_ring", tier: "outer"
  },
  far_southeast: {
    name: "Far Southeast / Abdullapurmet", lat: 17.3500, lng: 78.6500,
    zone_type: "outer_ring", tier: "outer"
  },
  far_south: {
    name: "Far South / Srisailam Road", lat: 17.1800, lng: 78.4600,
    zone_type: "outer_ring", tier: "outer"
  },
  far_southwest: {
    name: "Far Southwest / Chevella", lat: 17.3000, lng: 78.2200,
    zone_type: "outer_ring", tier: "outer"
  },
  far_west: {
    name: "Far West / Isnapur Outer", lat: 17.5000, lng: 78.2200,
    zone_type: "outer_ring", tier: "outer"
  },
  far_northwest: {
    name: "Far Northwest / Ameenpur Outer", lat: 17.5600, lng: 78.2800,
    zone_type: "outer_ring", tier: "outer"
  }
}

puts "  Zone centers defined: #{ZONE_CENTERS.size}"
puts "  By tier:"
tier_counts = ZONE_CENTERS.values.group_by { |z| z[:tier] }.transform_values(&:size)
tier_counts.each { |t, c| puts "    #{t}: #{c}" }
puts "  By type:"
type_counts = ZONE_CENTERS.values.group_by { |z| z[:zone_type] }.transform_values(&:size)
type_counts.sort_by { |_, v| -v }.each { |t, c| puts "    #{t}: #{c}" }

# =============================================================================
# STEP 4: VORONOI ASSIGNMENT — Assign each R7 cell to nearest zone center
# =============================================================================

puts "\nStep 4: Voronoi assignment (each R7 cell → nearest zone center)..."

# Haversine distance in meters
def haversine_m(lat1, lng1, lat2, lng2)
  r = 6_371_000 # Earth radius in meters
  dlat = (lat2 - lat1) * Math::PI / 180
  dlng = (lng2 - lng1) * Math::PI / 180
  a = Math.sin(dlat / 2)**2 +
      Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) *
      Math.sin(dlng / 2)**2
  2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
end

zone_cells = Hash.new { |h, k| h[k] = [] }
unassigned = 0

all_r7_cells.each do |hex, cell|
  nearest_zone = nil
  nearest_dist = Float::INFINITY

  ZONE_CENTERS.each do |zone_code, center|
    dist = haversine_m(cell[:lat], cell[:lng], center[:lat], center[:lng])
    if dist < nearest_dist
      nearest_dist = dist
      nearest_zone = zone_code
    end
  end

  if nearest_zone
    zone_cells[nearest_zone] << hex
    if VERBOSE
      puts "    #{hex} (#{cell[:lat].round(4)}, #{cell[:lng].round(4)}) → #{nearest_zone} (#{(nearest_dist / 1000).round(1)}km)"
    end
  else
    unassigned += 1
    puts "    WARNING: #{hex} unassigned!"
  end
end

puts "  Cells assigned: #{all_r7_cells.size - unassigned}"
puts "  Cells unassigned: #{unassigned}"
puts "  Zones with cells: #{zone_cells.size}"
puts "  Empty zones: #{ZONE_CENTERS.size - zone_cells.size}"

# Show zones with 0 cells (too close to another center)
empty_zones = ZONE_CENTERS.keys.select { |z| zone_cells[z].empty? }
if empty_zones.any?
  puts "  WARNING — Empty zones (will be merged into nearest neighbor):"
  empty_zones.each { |z| puts "    #{z}: #{ZONE_CENTERS[z][:name]}" }
end

# Stats
cell_counts = zone_cells.values.map(&:size)
puts "\n  Cell distribution:"
puts "    Min: #{cell_counts.min} cells"
puts "    Max: #{cell_counts.max} cells"
puts "    Avg: #{(cell_counts.sum.to_f / cell_counts.size).round(1)} cells"
puts "    Median: #{cell_counts.sort[cell_counts.size / 2]} cells"

# =============================================================================
# STEP 5: BUILD PRICING (city defaults × zone_type × tier adjustments)
# =============================================================================

puts "\nStep 5: Building pricing..."

defaults_config = YAML.load_file(DEFAULTS_PATH)
global_rates = defaults_config['global_time_rates']

TIME_BANDS = %w[early_morning morning_rush midday afternoon evening_rush night weekend_day weekend_night]
VEHICLES = %w[two_wheeler scooter mini_3w three_wheeler three_wheeler_ev tata_ace pickup_8ft eeco tata_407 canter_14ft]

# Zone type rate multipliers (relative to city defaults)
ZONE_TYPE_MULTIPLIERS = {
  'tech_corridor'          => 1.00,
  'business_cbd'           => 1.03,
  'airport_logistics'      => 1.08,
  'residential_growth'     => 0.97,
  'residential_dense'      => 1.00,
  'residential_mixed'      => 0.98,
  'traditional_commercial' => 1.02,
  'premium_residential'    => 1.05,
  'industrial'             => 0.95,
  'heritage_commercial'    => 1.02,
  'outer_ring'             => 0.93,
  'default'                => 1.00
}

# Tier adjustments (distance from core)
TIER_MULTIPLIERS = {
  'core'   => 1.00,
  'fringe' => 0.98,
  'suburb' => 0.95,
  'outer'  => 0.90
}

ZONE_TYPE_PRIORITIES = {
  'tech_corridor'          => 20,
  'business_cbd'           => 18,
  'airport_logistics'      => 16,
  'premium_residential'    => 19,
  'traditional_commercial' => 15,
  'heritage_commercial'    => 15,
  'residential_dense'      => 14,
  'industrial'             => 12,
  'residential_mixed'      => 12,
  'residential_growth'     => 10,
  'outer_ring'             => 8,
  'default'                => 5
}

def build_zone_pricing(global_rates, zone_type, tier)
  zt_mult = ZONE_TYPE_MULTIPLIERS[zone_type] || 1.0
  tier_mult = TIER_MULTIPLIERS[tier] || 1.0
  combined = zt_mult * tier_mult

  pricing = {}
  TIME_BANDS.each do |band|
    band_rates = global_rates[band]
    next unless band_rates

    pricing[band] = {}
    VEHICLES.each do |vehicle|
      vr = band_rates[vehicle]
      next unless vr
      pricing[band][vehicle] = {
        'base' => (vr['base'] * combined).round,
        'rate' => (vr['rate'] * combined).round
      }
    end
  end
  pricing
end

# =============================================================================
# STEP 6: GENERATE FRESH h3_zones.yml
# =============================================================================

puts "\nStep 6: Generating fresh h3_zones.yml..."

zones_yaml = {}

zone_cells.each do |zone_code, cells|
  center = ZONE_CENTERS[zone_code]
  next unless center # skip if center somehow missing

  pricing = build_zone_pricing(global_rates, center[:zone_type], center[:tier])

  zones_yaml[zone_code.to_s] = {
    'name'           => center[:name],
    'zone_type'      => center[:zone_type],
    'priority'       => ZONE_TYPE_PRIORITIES[center[:zone_type]] || 10,
    'active'         => true,
    'auto_generated' => false,
    'h3_cells_r7'    => cells.sort,
    'pricing'        => pricing
  }
end

h3_config = {
  'city_code'    => 'hyd',
  'version'      => '3.0',
  'generated_at' => Time.current.iso8601,
  'zones'        => zones_yaml
}

# =============================================================================
# STEP 7: WRITE (or preview)
# =============================================================================

if DRY_RUN
  puts "\n[DRY RUN] Would write #{zones_yaml.size} zones to #{YAML_PATH}"
  puts "[DRY RUN] No files modified."
else
  # Backup existing file
  if File.exist?(YAML_PATH)
    FileUtils.cp(YAML_PATH, BACKUP_PATH)
    puts "  Backed up existing file to: #{BACKUP_PATH}"
  end

  File.write(YAML_PATH, h3_config.to_yaml)
  puts "  Written #{zones_yaml.size} zones to #{YAML_PATH}"
end

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n#{'=' * 80}"
puts "SUMMARY"
puts '=' * 80
puts ""
puts "Zones: #{zones_yaml.size}"
puts "R7 cells: #{all_r7_cells.size} (#{(all_r7_cells.size * 5.16).round} km² coverage)"
puts "Unassigned cells: #{unassigned}"
puts "Empty zones (removed): #{empty_zones.size}"
puts ""
puts "By tier:"
zones_yaml.values.group_by { |z|
  center = ZONE_CENTERS.values.find { |c| c[:name] == z['name'] }
  center ? center[:tier] : 'unknown'
}.each { |t, zs| puts "  #{t}: #{zs.size} zones, #{zs.sum { |z| z['h3_cells_r7'].size }} cells" }
puts ""
puts "By zone type:"
zones_yaml.values.group_by { |z| z['zone_type'] }
  .sort_by { |_, v| -v.size }
  .each { |t, zs| puts "  #{t}: #{zs.size} zones, #{zs.sum { |z| z['h3_cells_r7'].size }} cells" }
puts ""
puts "Cell coverage verification:"
total_assigned = zone_cells.values.flatten.uniq.size
total_r7 = all_r7_cells.size
puts "  Total R7 in boundary: #{total_r7}"
puts "  Total assigned: #{total_assigned}"
puts "  Coverage: #{(total_assigned.to_f / total_r7 * 100).round(1)}%"

duplicates = zone_cells.values.flatten.size - zone_cells.values.flatten.uniq.size
puts "  Duplicate assignments: #{duplicates} (should be 0)"

if duplicates > 0
  puts "  ERROR: Duplicate cell assignments found! Voronoi should prevent this."
end

if total_assigned == total_r7 && duplicates == 0
  puts "\n  ✓ HONEYCOMB GUARANTEE: 100% coverage, 0 gaps, 0 overlaps"
else
  puts "\n  ✗ COVERAGE ISSUE: Check boundary and zone centers"
end

puts ""
puts "Next steps:"
puts "  1. Review zone assignments: VERBOSE=true DRY_RUN=true bundle exec ruby script/rewrite_zones_honeycomb.rb"
puts "  2. Sync to DB: rails zones:h3_sync[hyd]"
puts "  3. Verify in admin: http://localhost:3001/admin/zone_map"
puts "  4. Run pricing test: PRICING_MODE=calibration bundle exec ruby script/test_pricing_engine.rb"
puts '=' * 80
