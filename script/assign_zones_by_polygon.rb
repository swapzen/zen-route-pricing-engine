#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# Zone Polygon Assignment Script
# =============================================================================
#
# Assigns H3 R7 hexes to zones using polygon polyfill + priority-based overlap
# resolution. Replaces Voronoi-based assignment with boundary-aware priority system.
#
# Usage:
#   bundle exec ruby script/assign_zones_by_polygon.rb              # Full run
#   bundle exec ruby script/assign_zones_by_polygon.rb --dry-run    # Preview only
#   bundle exec ruby script/assign_zones_by_polygon.rb --verify     # Landmark test
#
# On first run, generates zone_boundaries.yml from hyderabad.yml bboxes.
# On subsequent runs, reads the existing zone_boundaries.yml (for iterative refinement).
# =============================================================================

require_relative "../config/environment"
require "yaml"

class ZonePolygonAssigner
  CITY_CODE = "hyd"
  CONFIG_DIR = Rails.root.join("config", "zones", "hyderabad")
  HYDERABAD_YML = Rails.root.join("config", "zones", "hyderabad.yml")
  H3_ZONES_FILE = CONFIG_DIR.join("h3_zones.yml")
  BOUNDARIES_FILE = CONFIG_DIR.join("zone_boundaries.yml")

  # Priority by zone_type — used for overlap resolution and new zone defaults.
  # Higher priority wins when two zone polygons overlap on the same H3 cell.
  # Same-priority zones use centroid distance tiebreak (closer center wins).
  ZONE_TYPE_PRIORITY = {
    "tech_corridor" => 20,
    "premium_residential" => 18,
    "business_cbd" => 18,
    "airport_logistics" => 15,
    "heritage_commercial" => 14,
    "traditional_commercial" => 13,
    "industrial" => 12,
    "residential_dense" => 10,
    "residential_mixed" => 8,
    "residential_growth" => 6,
    "outer_ring" => 5,
    "default" => 3
  }.freeze

  # Per-zone priority overrides (for overlap resolution only)
  PRIORITY_OVERRIDES = {
    "old_city" => 15,        # Heritage zone — beats surrounding traditional_commercial
    "dilsukhnagar" => 11,    # Beats lb_nagar_east (10) at the overlap boundary
    "uppal_corridor" => 9    # Corridor endpoint — beats nagole (8) overlap
  }.freeze

  # No bbox expansion — tight polygons from hyderabad.yml.
  # Unclaimed cells use nearest-bbox-edge + priority for assignment.
  BBOX_EXPANSION_DEG = 0.0

  # Zone consolidation: karwan → mehdipatnam, nampally+abids → nampally_abids
  MERGE_INTO = {
    "karwan" => "mehdipatnam",
    "nampally" => "nampally_abids",
    "abids" => "nampally_abids"
  }.freeze

  # Hyderabad service area (covers full GHMC + fringe)
  SERVICE_AREA = {
    lat_min: 17.20, lat_max: 17.67,
    lng_min: 78.22, lng_max: 78.72
  }.freeze

  # Landmark expectations: [name, lat, lng, expected_zone]
  LANDMARK_TESTS = [
    ["Charminar", 17.3616, 78.4747, "old_city"],
    ["Golconda Fort", 17.3833, 78.4011, "golconda"],
    ["RGIA Airport", 17.2403, 78.4294, "shamshabad"],
    ["Secunderabad Station", 17.4340, 78.5010, "secunderabad_cbd"],
    ["Nampally Station", 17.3880, 78.4730, "nampally_abids"],
    ["MGBS Bus Station", 17.3780, 78.4760, "nampally_abids"],
    ["Inorbit Mall Madhapur", 17.4355, 78.3855, "hitech_madhapur"],
    ["IKEA HiTech City", 17.4335, 78.3740, "hitech_madhapur"],
    ["Nexus Mall Kukatpally", 17.4900, 78.3900, "jntu_kukatpally"],
    ["Microsoft Gachibowli", 17.4270, 78.3390, "fin_district"],
    ["Apollo Jubilee Hills", 17.4260, 78.4070, "jubilee_hills"],
    ["GVK One Banjara Hills", 17.4230, 78.4490, "banjara_hills"],
    ["Dilsukhnagar", 17.3680, 78.5250, "dilsukhnagar"],
    ["Ameerpet", 17.4379, 78.4482, "ameerpet_core"],
    ["Begumpet", 17.4430, 78.4700, "begumpet"],
    ["Madhapur", 17.4430, 78.3930, "hitech_madhapur"],
    ["Kompally", 17.5420, 78.4850, "kompally"],
    ["Manikonda", 17.4050, 78.3870, "manikonda"],
    ["ISB Gachibowli", 17.4240, 78.3320, "fin_district"],
    ["Miyapur Metro", 17.4960, 78.3580, "miyapur"],
    ["LB Nagar", 17.3515, 78.5530, "lb_nagar_east"],
    ["Hussain Sagar", 17.4239, 78.4738, "khairatabad"],
    ["Birla Mandir", 17.4062, 78.4691, "goshamahal"],
    ["Continental Hospital", 17.4230, 78.3480, "fin_district"],
    ["KIMS Secunderabad", 17.4500, 78.4990, "secunderabad_cbd"],
    ["KPHB Colony", 17.4850, 78.4000, "alwyn_colony"],
    ["DPS Nacharam", 17.4320, 78.5410, "nacharam"],
    ["Sarath City Mall", 17.4270, 78.3680, "hitech_madhapur"],
    ["TCS Synergy Park", 17.4393, 78.3580, "fin_district"],
    ["Raheja Mindspace", 17.4410, 78.3820, "hitech_madhapur"],
    ["Oakridge Bachupally", 17.5440, 78.3870, "bachupally"],
    ["CHIREC Kondapur", 17.4570, 78.3640, "kondapur"],
    ["Infosys Pocharam", 17.4470, 78.5780, "nacharam"],
    ["DXC Manikonda", 17.4050, 78.3730, "manikonda"],
    ["Yashoda Somajiguda", 17.4300, 78.4710, "khairatabad"],
    ["JBS Secunderabad", 17.4480, 78.5000, "secunderabad_cbd"],
    ["Care Hospitals Banjara", 17.4130, 78.4380, "banjara_hills"],
  ].freeze

  def initialize(dry_run: false, verify_only: false)
    @dry_run = dry_run
    @verify_only = verify_only
  end

  def run
    if @verify_only
      run_landmark_verification
      return
    end

    puts "=== Zone Polygon Assignment ==="
    puts "Mode: #{@dry_run ? 'DRY RUN' : 'WRITE'}"
    puts

    # Step 1: Generate or load zone boundaries
    boundaries = load_or_generate_boundaries
    puts "Loaded #{boundaries.size} zone boundaries"
    puts

    # Step 2: Polyfill each zone polygon → candidate R7 cells
    cell_claims = polyfill_zones(boundaries)

    # Step 3: Resolve overlaps (priority wins, then centroid distance)
    assignments = resolve_overlaps(cell_claims)

    # Step 4: Fill unclaimed cells in service area → nearest zone
    assignments = fill_unclaimed(assignments, boundaries)

    # Step 5: Load existing pricing data to preserve
    existing_zones = load_existing_pricing

    # Check for zones with 0 cells
    zone_cells_check = Hash.new(0)
    assignments.each_value { |z| zone_cells_check[z] += 1 }
    empty_zones = boundaries.keys - zone_cells_check.keys
    if empty_zones.any?
      puts "--- Zones with 0 cells (absorbed by neighbors) ---"
      empty_zones.sort.each { |z| puts "  #{z}: #{boundaries[z]['zone_type']}" }
      puts
    end

    # Step 6: Write updated h3_zones.yml
    write_h3_zones(boundaries, assignments, existing_zones)

    # Step 7: Run landmark verification
    puts
    run_landmark_verification(assignments: assignments, boundaries: boundaries)
  end

  private

  # ---------------------------------------------------------------------------
  # Step 1: Boundaries
  # ---------------------------------------------------------------------------

  def load_or_generate_boundaries
    if File.exist?(BOUNDARIES_FILE)
      puts "Loading existing #{BOUNDARIES_FILE}..."
      config = YAML.load_file(BOUNDARIES_FILE)
      config["boundaries"]
    else
      puts "Generating #{BOUNDARIES_FILE} from hyderabad.yml bboxes..."
      generate_boundaries_from_bboxes
    end
  end

  def generate_boundaries_from_bboxes
    hyderabad = YAML.load_file(HYDERABAD_YML)
    existing_h3 = YAML.load_file(H3_ZONES_FILE)
    existing_priorities = (existing_h3["zones"] || {}).transform_values { |z| z["priority"] }

    boundaries = {}
    merge_sources = Hash.new { |h, k| h[k] = [] } # target → [source bounds]

    hyderabad["zones"].each do |zone_code, config|
      bounds = config["bounds"]
      zone_type = config["zone_type"]

      if MERGE_INTO.key?(zone_code)
        target = MERGE_INTO[zone_code]
        merge_sources[target] << bounds
        next
      end

      # Use zone_type-based priority for overlap resolution, with per-zone overrides
      priority = PRIORITY_OVERRIDES[zone_code] || ZONE_TYPE_PRIORITY[zone_type] || 5

      boundaries[zone_code] = {
        "name" => config["name"],
        "polygon" => bbox_to_polygon(bounds),
        "zone_type" => zone_type,
        "priority" => priority
      }
    end

    # Expand mehdipatnam to absorb karwan
    if boundaries["mehdipatnam"] && merge_sources["mehdipatnam"].any?
      orig_bounds = hyderabad["zones"]["mehdipatnam"]["bounds"]
      all_bounds = [orig_bounds] + merge_sources["mehdipatnam"]
      boundaries["mehdipatnam"]["polygon"] = bbox_to_polygon(expand_bounds(all_bounds))
      puts "  mehdipatnam: expanded to absorb karwan"
    end

    # Create nampally_abids from nampally + abids
    if merge_sources["nampally_abids"].any?
      combined = expand_bounds(merge_sources["nampally_abids"])
      boundaries["nampally_abids"] = {
        "name" => "Nampally Abids",
        "polygon" => bbox_to_polygon(combined),
        "zone_type" => "traditional_commercial",
        "priority" => existing_priorities["nampally"] || 18
      }
      puts "  nampally_abids: created from nampally + abids"
    end

    # Apply targeted boundary refinements to fix overlap issues at zone borders
    apply_boundary_refinements(boundaries)

    # Write zone_boundaries.yml
    output = {
      "city_code" => CITY_CODE,
      "version" => "1.0",
      "generated_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      "boundaries" => boundaries.sort.to_h
    }

    File.write(BOUNDARIES_FILE, output.to_yaml)
    puts "  Wrote #{BOUNDARIES_FILE} (#{boundaries.size} zones)"

    boundaries
  end

  # Targeted polygon adjustments based on landmark verification failures.
  # Each entry overrides a specific bbox edge to resolve boundary overlap.
  def apply_boundary_refinements(boundaries)
    refinements = {
      # Trim masab_tank north — GVK One is in Banjara Hills, not Masab Tank
      "masab_tank" => { lat_max: 17.42 },
      # Trim mehdipatnam north — Care Hospitals is in Banjara Hills
      "mehdipatnam" => { lat_max: 17.41 },
      # Expand banjara_hills south + east — capture GVK One & Care Hospitals; trim north for ameerpet_core
      "banjara_hills" => { lat_min: 17.40, lat_max: 17.43, lng_max: 78.47 },
      # Trim santoshnagar east — Dilsukhnagar landmark is in dilsukhnagar
      "santoshnagar" => { lng_max: 78.52 },
      # Trim yousufguda east — Begumpet area belongs to begumpet
      "yousufguda" => { lng_max: 78.455 },
      # Expand nacharam west — DPS Nacharam should be in nacharam (industrial > tarnaka)
      "nacharam" => { lng_min: 78.52 },
      # Expand dilsukhnagar south — R7 cell center drifts below bbox at the landmark
      "dilsukhnagar" => { lat_min: 17.35 },
      # Trim ameerpet_core east — free up hex around lng 78.46 for begumpet
      "ameerpet_core" => { lng_max: 78.455 }
    }

    refinements.each do |zone_code, overrides|
      next unless boundaries[zone_code]
      poly = boundaries[zone_code]["polygon"]
      lats = poly.map { |c| c[0] }
      lngs = poly.map { |c| c[1] }

      lat_min = overrides[:lat_min] || lats.min
      lat_max = overrides[:lat_max] || lats.max
      lng_min = overrides[:lng_min] || lngs.min
      lng_max = overrides[:lng_max] || lngs.max

      boundaries[zone_code]["polygon"] = [
        [lat_min, lng_min], [lat_min, lng_max], [lat_max, lng_max], [lat_max, lng_min]
      ]
      puts "  #{zone_code}: boundary refined"
    end
  end

  # ---------------------------------------------------------------------------
  # Step 2: Polyfill
  # ---------------------------------------------------------------------------

  def polyfill_zones(boundaries)
    cell_claims = {} # { hex_str => [[zone_code, priority, distance_to_centroid], ...] }
    total_polyfill = 0

    boundaries.each do |zone_code, config|
      polygon = config["polygon"]
      priority = config["priority"]

      # H3.polyfill expects [[[lat,lng], ...]]
      h3_polygon = [polygon]

      begin
        hex_integers = H3.polyfill(h3_polygon, 7)
      rescue => e
        puts "  WARN: polyfill failed for #{zone_code}: #{e.message}"
        next
      end

      total_polyfill += hex_integers.size

      # Centroid for distance tiebreaking
      centroid_lat = polygon.sum { |c| c[0] } / polygon.size.to_f
      centroid_lng = polygon.sum { |c| c[1] } / polygon.size.to_f

      hex_integers.each do |h3_int|
        hex = h3_int.to_s(16)
        cell_lat, cell_lng = H3.to_geo_coordinates(h3_int)
        dist = Math.sqrt((cell_lat - centroid_lat)**2 + (cell_lng - centroid_lng)**2)

        cell_claims[hex] ||= []
        cell_claims[hex] << [zone_code, priority, dist]
      end
    end

    puts "--- Polyfill Results ---"
    puts "  Total polyfill claims: #{total_polyfill}"
    puts "  Unique R7 cells claimed: #{cell_claims.size}"
    multi = cell_claims.count { |_, claims| claims.size > 1 }
    puts "  Cells with overlapping claims: #{multi}"
    puts

    cell_claims
  end

  # ---------------------------------------------------------------------------
  # Step 3: Overlap resolution
  # ---------------------------------------------------------------------------

  def resolve_overlaps(cell_claims)
    assignments = {}

    cell_claims.each do |hex, claims|
      if claims.size == 1
        assignments[hex] = claims[0][0]
      else
        # Highest priority wins, then closest to centroid
        winner = claims.sort_by { |c| [-c[1], c[2]] }.first
        assignments[hex] = winner[0]
      end
    end

    # Print per-zone assignment counts
    zone_counts = Hash.new(0)
    assignments.each_value { |z| zone_counts[z] += 1 }

    puts "--- Assignments after overlap resolution ---"
    zone_counts.sort_by { |_, c| -c }.each do |zone, count|
      puts "  #{zone}: #{count} cells"
    end
    puts "  TOTAL: #{assignments.size}"
    puts

    assignments
  end

  # ---------------------------------------------------------------------------
  # Step 4: Fill unclaimed service area cells
  # ---------------------------------------------------------------------------

  def fill_unclaimed(assignments, boundaries)
    service_polygon = [[
      [SERVICE_AREA[:lat_min], SERVICE_AREA[:lng_min]],
      [SERVICE_AREA[:lat_min], SERVICE_AREA[:lng_max]],
      [SERVICE_AREA[:lat_max], SERVICE_AREA[:lng_max]],
      [SERVICE_AREA[:lat_max], SERVICE_AREA[:lng_min]]
    ]]

    all_service_cells = H3.polyfill(service_polygon, 7).map { |h| h.to_s(16) }.to_set
    assigned_set = assignments.keys.to_set
    unclaimed = all_service_cells - assigned_set

    puts "--- Service Area Fill ---"
    puts "  Service area R7 cells: #{all_service_cells.size}"
    puts "  Already assigned: #{assigned_set.size}"
    puts "  Unclaimed: #{unclaimed.size}"

    if unclaimed.any?
      # Pre-compute bbox bounds for each zone (for edge-distance calculation)
      zone_bboxes = {}
      boundaries.each do |zone_code, config|
        poly = config["polygon"]
        lats = poly.map { |c| c[0] }
        lngs = poly.map { |c| c[1] }
        zone_bboxes[zone_code] = {
          lat_min: lats.min, lat_max: lats.max,
          lng_min: lngs.min, lng_max: lngs.max,
          centroid: [(lats.min + lats.max) / 2.0, (lngs.min + lngs.max) / 2.0],
          priority: config["priority"]
        }
      end

      # Track which zones got unclaimed cells
      unclaimed_assignments = Hash.new(0)

      unclaimed.each do |hex|
        h3_int = hex.to_i(16)
        cell_lat, cell_lng = H3.to_geo_coordinates(h3_int)

        # Score each zone by: [edge_distance, -priority, centroid_distance]
        # Lowest score wins (closer edge, higher priority, closer centroid)
        best_zone = zone_bboxes.min_by do |_, bb|
          # Distance to nearest point on bbox edge (0 if inside)
          dlat = [0.0, bb[:lat_min] - cell_lat, cell_lat - bb[:lat_max]].max
          dlng = [0.0, bb[:lng_min] - cell_lng, cell_lng - bb[:lng_max]].max
          edge_dist = Math.sqrt(dlat**2 + dlng**2)

          cdist = Math.sqrt((cell_lat - bb[:centroid][0])**2 + (cell_lng - bb[:centroid][1])**2)
          [edge_dist, -bb[:priority], cdist]
        end[0]

        assignments[hex] = best_zone
        unclaimed_assignments[best_zone] += 1
      end

      puts "  Unclaimed cells assigned by nearest-bbox-edge:"
      unclaimed_assignments.sort_by { |_, c| -c }.first(15).each do |zone, count|
        puts "    #{zone}: +#{count}"
      end
      puts "    ... (#{unclaimed_assignments.size} zones total)" if unclaimed_assignments.size > 15
      puts "  Total after fill: #{assignments.size}"
    end

    puts
    assignments
  end

  # ---------------------------------------------------------------------------
  # Step 5: Load existing pricing
  # ---------------------------------------------------------------------------

  def load_existing_pricing
    return {} unless File.exist?(H3_ZONES_FILE)
    data = YAML.load_file(H3_ZONES_FILE)
    data["zones"] || {}
  end

  # ---------------------------------------------------------------------------
  # Step 6: Write h3_zones.yml
  # ---------------------------------------------------------------------------

  def write_h3_zones(boundaries, assignments, existing_zones)
    # Group cells by zone
    zone_cells = Hash.new { |h, k| h[k] = [] }
    assignments.each { |hex, zone| zone_cells[zone] << hex }

    output_zones = {}

    boundaries.each do |zone_code, config|
      cells = zone_cells[zone_code]&.sort || []
      next if cells.empty?

      # Preserve existing pricing
      pricing = existing_zones.dig(zone_code, "pricing")

      # For nampally_abids (new zone), use nampally's pricing as base
      if zone_code == "nampally_abids" && pricing.nil?
        pricing = existing_zones.dig("nampally", "pricing") || existing_zones.dig("abids", "pricing")
      end

      # Use original h3_zones.yml priority if it exists (for pricing resolver),
      # otherwise derive from zone_type
      original_priority = existing_zones.dig(zone_code, "priority") ||
                          ZONE_TYPE_PRIORITY[config["zone_type"]] || 5

      output_zones[zone_code] = {
        "name" => config["name"],
        "zone_type" => config["zone_type"],
        "priority" => original_priority,
        "active" => true,
        "auto_generated" => false,
        "h3_cells_r7" => cells
      }
      output_zones[zone_code]["pricing"] = pricing if pricing
    end

    output = {
      "city_code" => CITY_CODE,
      "version" => "2.0",
      "generated_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      "zones" => output_zones.sort.to_h
    }

    if @dry_run
      puts "=== DRY RUN — Would write h3_zones.yml ==="
      puts "  Zones: #{output_zones.size}"
      puts "  Total R7 cells: #{assignments.size}"
      puts "  (No files modified)"
    else
      File.write(H3_ZONES_FILE, output.to_yaml)
      puts "=== Wrote h3_zones.yml ==="
      puts "  Zones: #{output_zones.size}"
      puts "  Total R7 cells: #{assignments.size}"
    end
  end

  # ---------------------------------------------------------------------------
  # Landmark Verification
  # ---------------------------------------------------------------------------

  def run_landmark_verification(assignments: nil, boundaries: nil)
    puts "=== Landmark Verification ==="

    # If no assignments provided, resolve from the current h3_zones.yml
    if assignments.nil?
      h3_data = YAML.load_file(H3_ZONES_FILE)
      zones = h3_data["zones"] || {}

      # Build R7 → zone lookup
      r7_map = {}
      zones.each do |zone_code, config|
        (config["h3_cells_r7"] || []).each do |hex|
          r7_map[hex] = zone_code
        end
      end

      pass = 0
      fail_count = 0

      LANDMARK_TESTS.each do |name, lat, lng, expected|
        h3_int = H3.from_geo_coordinates([lat, lng], 7)
        hex = h3_int.to_s(16)
        actual = r7_map[hex]

        if actual == expected
          pass += 1
          puts "  PASS  #{name} → #{actual}"
        else
          fail_count += 1
          puts "  FAIL  #{name} → #{actual || 'UNASSIGNED'} (expected #{expected})"
        end
      end
    else
      # Use provided assignments (from in-memory run)
      pass = 0
      fail_count = 0

      LANDMARK_TESTS.each do |name, lat, lng, expected|
        h3_int = H3.from_geo_coordinates([lat, lng], 7)
        hex = h3_int.to_s(16)
        actual = assignments[hex]

        if actual == expected
          pass += 1
          puts "  PASS  #{name} → #{actual}"
        else
          fail_count += 1
          puts "  FAIL  #{name} → #{actual || 'UNASSIGNED'} (expected #{expected})"
        end
      end
    end

    puts
    puts "Results: #{pass}/#{LANDMARK_TESTS.size} passed, #{fail_count} failed"
    puts fail_count == 0 ? "ALL LANDMARKS PASS" : "#{fail_count} FAILURES — boundary refinement needed"
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def bbox_to_polygon(bounds, expand: BBOX_EXPANSION_DEG)
    lat_min = bounds["lat_min"].to_f - expand
    lat_max = bounds["lat_max"].to_f + expand
    lng_min = bounds["lng_min"].to_f - expand
    lng_max = bounds["lng_max"].to_f + expand
    [
      [lat_min, lng_min],
      [lat_min, lng_max],
      [lat_max, lng_max],
      [lat_max, lng_min]
    ]
  end

  def expand_bounds(bounds_list)
    {
      "lat_min" => bounds_list.map { |b| b["lat_min"].to_f }.min,
      "lat_max" => bounds_list.map { |b| b["lat_max"].to_f }.max,
      "lng_min" => bounds_list.map { |b| b["lng_min"].to_f }.min,
      "lng_max" => bounds_list.map { |b| b["lng_max"].to_f }.max
    }
  end
end

# --- CLI ---
dry_run = ARGV.include?("--dry-run")
verify_only = ARGV.include?("--verify")

ZonePolygonAssigner.new(dry_run: dry_run, verify_only: verify_only).run
