# frozen_string_literal: true

# =============================================================================
# H3 Zone Mapping Rake Tasks
# =============================================================================
# Populate H3 hexagonal grid mappings for zones and supply density.
# Uses H3.polyfill for accurate zone-to-hex conversion (no point sampling).
# Generates R7 and R8 hex mappings for dual-resolution lookup.
#
# USAGE:
#   rails zones:populate_h3[hyd]
#   rails zones:seed_supply_density[hyd]
# =============================================================================

namespace :zones do
  desc "Populate H3 hexagonal grid mappings for all zones in a city"
  task :populate_h3, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    unless defined?(H3)
      puts "H3 gem not available. Run: bundle install"
      exit 1
    end

    zones = Zone.for_city(city_code).active
    puts "Populating H3 mappings for #{zones.count} zones in #{city_code}..."

    total_r7 = 0
    total_r8 = 0

    zones.find_each do |zone|
      next unless zone.lat_min && zone.lat_max && zone.lng_min && zone.lng_max

      # Build polygon from bounding box for polyfill
      polygon = build_bbox_polygon(zone)

      # Polyfill at R7 and R8
      r7_hexes = H3.polyfill(polygon, 7)
      r8_hexes = H3.polyfill(polygon, 8)

      # Build R8 -> R7 parent lookup
      r8_by_r7_parent = {}
      r8_hexes.each do |r8_int|
        r7_parent = H3.parent(r8_int, 7)
        r8_by_r7_parent[r7_parent] ||= []
        r8_by_r7_parent[r7_parent] << r8_int
      end

      # Ensure all R7 hexes from polyfill are included
      all_r7_set = Set.new(r7_hexes)
      r8_by_r7_parent.each_key { |r7_int| all_r7_set.add(r7_int) }

      # Create/update one mapping per R7 cell, with a representative R8 index
      all_r7_set.each do |r7_int|
        r7_hex = r7_int.to_s(16)

        # Check if this R7 cell is shared with another zone (boundary)
        existing = ZoneH3Mapping.find_zones_for_r7(r7_hex, city_code).where.not(zone_id: zone.id)
        is_boundary = existing.exists?

        mapping = ZoneH3Mapping.find_or_initialize_by(
          h3_index_r7: r7_hex,
          zone_id: zone.id
        )

        # Pick a representative R8 child from this zone's polyfill
        r8_children = r8_by_r7_parent[r7_int] || []
        representative_r8 = r8_children.first

        mapping.assign_attributes(
          city_code: city_code,
          is_boundary: is_boundary,
          h3_index_r8: representative_r8&.to_s(16)
        )

        if is_boundary
          # Also mark existing mappings for this R7 as boundary
          existing.update_all(is_boundary: true)
        end

        mapping.save! if mapping.changed? || mapping.new_record?
        total_r7 += 1
      end

      total_r8 += r8_hexes.size

      # Update zone's H3 index arrays
      zone_r7s = ZoneH3Mapping.where(zone_id: zone.id).pluck(:h3_index_r7).uniq
      zone_r9s = ZoneH3Mapping.where(zone_id: zone.id).where.not(h3_index_r9: nil).pluck(:h3_index_r9).uniq
      zone.update!(h3_indexes_r7: zone_r7s, h3_indexes_r9: zone_r9s)

      puts "  #{zone.zone_code}: #{zone_r7s.count} R7 cells, #{r8_hexes.size} R8 cells"
    end

    # Build in-memory hash map for fast lookups
    map_stats = RoutePricing::Services::H3ZoneResolver.build_city_map(city_code)
    puts "\nIn-memory map loaded: #{map_stats[:r8]} R8 entries, #{map_stats[:r7]} R7 entries"
    puts "Done! Total: #{total_r7} R7 mappings, #{total_r8} R8 cells polyfilled"
  end

  desc "Seed H3 supply density defaults for a city"
  task :seed_supply_density, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    unless defined?(H3)
      puts "H3 gem not available. Run: bundle install"
      exit 1
    end

    # Get unique R7 cells from zone_h3_mappings
    r7_cells = ZoneH3Mapping.for_city(city_code).distinct.pluck(:h3_index_r7)
    puts "Seeding supply density for #{r7_cells.count} R7 cells in #{city_code}..."

    created = 0
    time_bands = %w[morning afternoon evening]

    r7_cells.each do |r7_hex|
      # Get zone for this cell to determine zone-type default
      mapping = ZoneH3Mapping.for_city(city_code).for_r7(r7_hex).includes(:zone).first
      zone = mapping&.zone
      avg_distance = zone_type_pickup_distance(zone&.zone_type)

      time_bands.each do |time_band|
        density = H3SupplyDensity.find_or_initialize_by(
          h3_index_r7: r7_hex,
          city_code: city_code,
          time_band: time_band
        )

        next unless density.new_record?

        density.assign_attributes(
          avg_pickup_distance_m: avg_distance,
          estimated_driver_count: 0,
          zone_type_default: true
        )
        density.save!
        created += 1
      end
    end

    puts "Done! Created #{created} supply density records"
  end
end

def build_bbox_polygon(zone)
  lat_min = zone.lat_min.to_f
  lat_max = zone.lat_max.to_f
  lng_min = zone.lng_min.to_f
  lng_max = zone.lng_max.to_f

  # H3.polyfill expects [[[lat,lng], [lat,lng], ...]] -- outer array wraps the polygon
  # No closing point needed
  [[[lat_min, lng_min], [lat_min, lng_max], [lat_max, lng_max], [lat_max, lng_min]]]
end

def zone_type_pickup_distance(zone_type)
  case zone_type
  when 'tech_corridor', 'business_cbd' then 2000
  when 'residential_dense', 'residential_mixed' then 3000
  when 'residential_growth' then 3500
  when 'airport_logistics' then 5000
  when 'industrial', 'outer_ring' then 4000
  else 3000
  end
end
