# frozen_string_literal: true

# =============================================================================
# H3 Zone Mapping Rake Tasks
# =============================================================================
# Populate H3 hexagonal grid mappings for zones and supply density.
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
    total_r9 = 0

    zones.find_each do |zone|
      next unless zone.lat_min && zone.lat_max && zone.lng_min && zone.lng_max

      # Compute R7 cells covering the zone bounding box
      r7_cells = compute_r7_cells_for_bbox(zone)

      # Find boundary cells (cells that map to multiple zones)
      r7_cells.each do |r7_hex|
        existing = ZoneH3Mapping.find_zones_for_r7(r7_hex, city_code).where.not(zone_id: zone.id)
        is_boundary = existing.exists?

        mapping = ZoneH3Mapping.find_or_initialize_by(
          h3_index_r7: r7_hex,
          zone_id: zone.id
        )

        mapping.assign_attributes(
          city_code: city_code,
          is_boundary: is_boundary
        )

        if is_boundary
          # Compute R9 children for boundary disambiguation
          r9_children = H3.to_children(r7_hex.to_i(16), 9)
          r9_children.each do |r9_int|
            r9_hex = r9_int.to_s(16)
            r9_lat, r9_lng = H3.to_geo(r9_int)

            # Check which zone actually contains this R9 cell center
            if zone.contains_point?(r9_lat, r9_lng)
              mapping.h3_index_r9 = r9_hex unless mapping.h3_index_r9
              total_r9 += 1
            end
          end

          # Also mark existing mappings for this R7 as boundary
          existing.update_all(is_boundary: true)
        end

        mapping.save! if mapping.changed? || mapping.new_record?
        total_r7 += 1
      end

      # Update zone's H3 index arrays
      zone_r7s = ZoneH3Mapping.where(zone_id: zone.id).pluck(:h3_index_r7).uniq
      zone_r9s = ZoneH3Mapping.where(zone_id: zone.id).where.not(h3_index_r9: nil).pluck(:h3_index_r9).uniq
      zone.update!(h3_indexes_r7: zone_r7s, h3_indexes_r9: zone_r9s)

      puts "  #{zone.zone_code}: #{zone_r7s.count} R7 cells, #{zone_r9s.count} R9 cells"
    end

    puts "\nDone! Total: #{total_r7} R7 mappings, #{total_r9} R9 mappings"
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

def compute_r7_cells_for_bbox(zone)
  # Sample points within the bounding box and collect unique R7 cells
  lat_step = 0.003  # ~330m at equator, good for R7 (~1.2km edge)
  lng_step = 0.003

  cells = Set.new
  lat = zone.lat_min.to_f

  while lat <= zone.lat_max.to_f
    lng = zone.lng_min.to_f
    while lng <= zone.lng_max.to_f
      h3_int = H3.from_geo_input([lat, lng], 7)
      cells.add(h3_int.to_s(16))
      lng += lng_step
    end
    lat += lat_step
  end

  # Also sample the corners and edges
  corners = [
    [zone.lat_min, zone.lng_min], [zone.lat_min, zone.lng_max],
    [zone.lat_max, zone.lng_min], [zone.lat_max, zone.lng_max]
  ]
  corners.each do |lat, lng|
    h3_int = H3.from_geo_input([lat.to_f, lng.to_f], 7)
    cells.add(h3_int.to_s(16))
  end

  cells.to_a
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
