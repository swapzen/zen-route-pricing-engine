# frozen_string_literal: true

namespace :zones do
  desc 'Diagnose zone resolution for calibration endpoints'
  task :diagnose, [:city] => :environment do |_t, args|
    city = args[:city] || 'hyd'

    # 10 calibration routes from test_pricing_engine.rb
    routes = [
      { name: 'Gowlidoddi → Storable', pickup: [17.4293, 78.3370], drop: [17.4394, 78.3577] },
      { name: 'Gowlidoddi → DispatchTrack', pickup: [17.4293, 78.3370], drop: [17.4406, 78.3499] },
      { name: 'LB Nagar → TCS Synergy', pickup: [17.3515, 78.5530], drop: [17.3817, 78.4801] },
      { name: 'Gowlidoddi → Ameerpet Metro', pickup: [17.4293, 78.3370], drop: [17.4379, 78.4482] },
      { name: 'LB Nagar → Shantiniketan', pickup: [17.3667, 78.5167], drop: [17.3700, 78.5180] },
      { name: 'Ameerpet → Nexus Mall', pickup: [17.4379, 78.4482], drop: [17.4900, 78.3900] },
      { name: 'JNTU → Charminar', pickup: [17.4900, 78.3900], drop: [17.3616, 78.4747] },
      { name: 'Vanasthali → Charminar', pickup: [17.4000, 78.5000], drop: [17.3616, 78.4747] },
      { name: 'AMB Cinemas → Ayyappa', pickup: [17.4480, 78.3900], drop: [17.4500, 78.4000] },
      { name: 'Ayyappa → Gowlidoddi', pickup: [17.4500, 78.4000], drop: [17.4293, 78.3370] }
    ]

    resolver = RoutePricing::Services::H3ZoneResolver.new(city)

    puts "\n#{'=' * 100}"
    puts "Zone Resolution Diagnostics for #{city.upcase}"
    puts "#{'=' * 100}\n\n"

    all_points = []
    routes.each_with_index do |route, idx|
      all_points << { route: idx + 1, name: route[:name], type: 'PICKUP', lat: route[:pickup][0], lng: route[:pickup][1] }
      all_points << { route: idx + 1, name: route[:name], type: 'DROP', lat: route[:drop][0], lng: route[:drop][1] }
    end

    all_points.each do |point|
      lat, lng = point[:lat], point[:lng]

      # H3 resolution
      h3_r7_int = H3.from_geo_coordinates([lat.to_f, lng.to_f], 7)
      h3_r7_hex = h3_r7_int.to_s(16)
      h3_r8_int = H3.from_geo_coordinates([lat.to_f, lng.to_f], 8)
      h3_r8_hex = h3_r8_int.to_s(16)

      h3_zone = resolver.resolve(lat, lng)

      # BBox resolution (manual scan)
      bbox_zones = Zone.where(city: city, status: true)
        .order(priority: :desc, zone_code: :asc)
        .select { |z| z.lat_min && lat >= z.lat_min && lat <= z.lat_max && lng >= z.lng_min && lng <= z.lng_max }
      bbox_zone = bbox_zones.first

      # Check H3 mapping
      h3_mapping = ZoneH3Mapping.where(h3_index_r7: h3_r7_hex, city_code: city).includes(:zone)
      mapped_zones = h3_mapping.map { |m| "#{m.zone.zone_code}(p#{m.zone.priority})" }.join(', ')

      # Conflict detection
      conflict = h3_zone && bbox_zone && h3_zone.id != bbox_zone.id

      puts "Route #{point[:route]}: #{point[:name]} — #{point[:type]}"
      puts "  Coords: #{lat}, #{lng}"
      puts "  H3 R7: #{h3_r7_hex} | R8: #{h3_r8_hex}"
      puts "  H3 Zone: #{h3_zone&.zone_code || 'NIL'} (#{h3_zone&.zone_type})"
      puts "  BBox Zone: #{bbox_zone&.zone_code || 'NIL'} (#{bbox_zone&.zone_type})"
      puts "  H3 Mappings: #{mapped_zones.presence || 'NONE'}"
      puts "  BBox Candidates: #{bbox_zones.map { |z| "#{z.zone_code}(p#{z.priority})" }.join(', ')}"
      puts "  ⚠️  CONFLICT: H3=#{h3_zone&.zone_code} vs BBox=#{bbox_zone&.zone_code}" if conflict
      puts "  ⚠️  NO H3 MAPPING for #{h3_r7_hex}" if h3_mapping.empty?
      puts ""
    end

    # Overlap analysis
    puts "\n#{'=' * 100}"
    puts "H3 Cell Overlap Analysis"
    puts "#{'=' * 100}\n\n"

    overlaps = ZoneH3Mapping.where(city_code: city)
      .group(:h3_index_r7)
      .having('COUNT(DISTINCT zone_id) > 1')
      .count

    if overlaps.any?
      puts "Found #{overlaps.size} R7 cells claimed by multiple zones:\n\n"
      overlaps.each do |h3_hex, count|
        mappings = ZoneH3Mapping.where(h3_index_r7: h3_hex, city_code: city).includes(:zone)
        zones = mappings.map { |m| "#{m.zone.zone_code}(p#{m.zone.priority})" }.join(' vs ')
        puts "  #{h3_hex}: #{zones} (#{count} zones)"
      end
    else
      puts "No overlapping H3 cells found."
    end

    puts "\n#{'=' * 100}"
    puts "Done"
    puts "#{'=' * 100}\n"
  end
end
