# frozen_string_literal: true
# Verify all zones in Hyderabad - boundaries, types, and sample coordinates

puts "=" * 80
puts "== ZONE VERIFICATION FOR HYDERABAD =="
puts "=" * 80

zones = Zone.for_city('hyd').active.order(:zone_code)

puts "\n📍 ZONES OVERVIEW:"
puts "-" * 80
puts sprintf("%-20s | %-18s | %-10s | %s", "Zone Code", "Zone Type", "Priority", "Bounding Box")
puts "-" * 80

zones.each do |z|
  bounds = if z.respond_to?(:min_lat) && z.min_lat
    "(#{z.min_lat.round(4)}, #{z.min_lng.round(4)}) to (#{z.max_lat.round(4)}, #{z.max_lng.round(4)})"
  elsif z.respond_to?(:center_lat)
    "center: (#{z.center_lat}, #{z.center_lng}), radius: #{z.radius_km rescue 'N/A'}km"
  else
    "Polygon/Custom bounds"
  end
  puts sprintf("%-20s | %-18s | %-10s | %s", z.zone_code, z.zone_type, z.priority || 0, bounds)
end

puts "\n" + "=" * 80
puts "== ZONE DETAILS WITH SAMPLE COORDINATES =="
puts "=" * 80

zones.each do |z|
  puts "\n📍 #{z.zone_code.upcase} (#{z.zone_type})"
  puts "   Priority: #{z.priority || 0}"
  
  # Try to get bounds
  if z.respond_to?(:min_lat) && z.min_lat
    puts "   Bounds: (#{z.min_lat}, #{z.min_lng}) to (#{z.max_lat}, #{z.max_lng})"
    # Generate center point
    center_lat = (z.min_lat + z.max_lat) / 2.0
    center_lng = (z.min_lng + z.max_lng) / 2.0
    puts "   📌 Sample INTRA-ZONE coordinates:"
    puts "      Center: (#{center_lat.round(4)}, #{center_lng.round(4)})"
    
    # Generate two points within the zone for intra-zone testing
    lat_range = z.max_lat - z.min_lat
    lng_range = z.max_lng - z.min_lng
    p1_lat = z.min_lat + lat_range * 0.3
    p1_lng = z.min_lng + lng_range * 0.3
    p2_lat = z.min_lat + lat_range * 0.7
    p2_lng = z.min_lng + lng_range * 0.7
    puts "      Point A: (#{p1_lat.round(4)}, #{p1_lng.round(4)})"
    puts "      Point B: (#{p2_lat.round(4)}, #{p2_lng.round(4)})"
  end
  
  # Check pricing
  zvp_count = ZoneVehiclePricing.where(zone: z, active: true).count
  puts "   💰 Zone Vehicle Pricings: #{zvp_count} active"
  
  # Check time pricings
  if zvp_count > 0
    sample_zvp = ZoneVehiclePricing.find_by(zone: z, vehicle_type: 'two_wheeler', active: true)
    if sample_zvp
      time_count = sample_zvp.time_pricings.active.count
      puts "   ⏰ Time Pricings for 2W: #{time_count} time bands"
      sample_zvp.time_pricings.active.each do |tp|
        puts "      - #{tp.time_band}: base=₹#{tp.base_fare_paise/100.0}, rate=₹#{tp.per_km_rate_paise/100.0}/km"
      end
    end
  end
end

puts "\n" + "=" * 80
puts "== CORRIDOR OVERVIEW (Zone Pairs) =="
puts "=" * 80

corridors = ZonePairVehiclePricing.where(city_code: 'hyd', active: true)
                                   .select(:from_zone_id, :to_zone_id)
                                   .distinct

puts "\n🛣️  EXISTING CORRIDORS:"
corridor_pairs = corridors.map do |c|
  from = Zone.find(c.from_zone_id).zone_code
  to = Zone.find(c.to_zone_id).zone_code
  [from, to]
end.uniq

corridor_pairs.each do |from, to|
  sample = ZonePairVehiclePricing.find_by(
    city_code: 'hyd',
    from_zone_id: Zone.find_by(zone_code: from).id,
    to_zone_id: Zone.find_by(zone_code: to).id,
    vehicle_type: 'two_wheeler',
    active: true
  )
  if sample
    puts "   #{from} → #{to}: base=₹#{sample.base_fare_paise/100.0}, rate=₹#{sample.per_km_rate_paise/100.0}/km"
  else
    puts "   #{from} → #{to}: (no 2W pricing)"
  end
end

puts "\n" + "=" * 80
puts "== MISSING CORRIDORS =="
puts "=" * 80

zone_codes = zones.pluck(:zone_code)
existing = corridor_pairs.map { |f, t| "#{f}→#{t}" }

puts "\n⚠️  Zone pairs WITHOUT corridor pricing:"
zone_codes.each do |from|
  zone_codes.each do |to|
    next if from == to
    key = "#{from}→#{to}"
    unless existing.include?(key)
      puts "   #{key}"
    end
  end
end

puts "\n✅ Zone verification complete!"
