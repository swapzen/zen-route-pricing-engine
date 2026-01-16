# frozen_string_literal: true
#
# Comprehensive Hyderabad Zone Verification
# Verifies zone coverage, boundaries, and generates test routes

puts "=" * 100
puts "🗺️  HYDERABAD ZONE VERIFICATION & TEST ROUTE GENERATOR"
puts "=" * 100

# ============================================================================
# PART 1: LIST ALL ACTIVE ZONES
# ============================================================================
puts "\n📍 ACTIVE ZONES IN HYDERABAD:\n"
puts "-" * 100
puts "| #{'Zone Code'.ljust(20)} | #{'Type'.ljust(22)} | #{'Lat Range'.ljust(18)} | #{'Lng Range'.ljust(18)} | #{'Geom'.ljust(8)} |"
puts "-" * 100

Zone.for_city('hyd').active.order(:zone_type, :zone_code).each_with_index do |z, i|
  lat_range = "#{z.lat_min&.round(4)} - #{z.lat_max&.round(4)}"
  lng_range = "#{z.lng_min&.round(4)} - #{z.lng_max&.round(4)}"
  geom = z.geometry_type || 'bbox'
  puts "| #{z.zone_code.ljust(20)} | #{z.zone_type.ljust(22)} | #{lat_range.ljust(18)} | #{lng_range.ljust(18)} | #{geom.ljust(8)} |"
end
puts "-" * 100
puts "Total active zones: #{Zone.for_city('hyd').active.count}"

# ============================================================================
# PART 2: VERIFY KEY LOCATIONS MAP TO CORRECT ZONES
# ============================================================================
puts "\n\n📌 KEY LOCATIONS ZONE MAPPING:\n"
puts "-" * 100

# Real Hyderabad locations with expected zones
KEY_LOCATIONS = [
  # Tech Corridor
  { name: 'Cyber Towers (HITEC)', lat: 17.4504, lng: 78.3810, expected: 'hitech_madhapur' },
  { name: 'Inorbit Mall', lat: 17.4352, lng: 78.3865, expected: 'hitech_madhapur' },
  { name: 'Raheja IT Park (Gachibowli)', lat: 17.4293, lng: 78.3370, expected: 'fin_district' },
  { name: 'ISB Hyderabad', lat: 17.4189, lng: 78.3423, expected: 'fin_district' },
  { name: 'TCS Synergy Park', lat: 17.3817, lng: 78.4801, expected: 'tcs_synergy' },
  
  # Business CBD
  { name: 'Ameerpet Metro', lat: 17.4379, lng: 78.4482, expected: 'ameerpet_core' },
  { name: 'Panjagutta', lat: 17.4320, lng: 78.4510, expected: 'ameerpet_core' },
  { name: 'Secunderabad Railway', lat: 17.4339, lng: 78.5011, expected: 'secunderabad' },
  { name: 'Paradise Circle', lat: 17.4447, lng: 78.4829, expected: 'secunderabad' },
  
  # Residential Dense
  { name: 'LB Nagar Metro', lat: 17.3515, lng: 78.5530, expected: 'lb_nagar_east' },
  { name: 'Dilsukhnagar', lat: 17.3687, lng: 78.5399, expected: 'lb_nagar_east' },
  { name: 'Vanasthalipuram', lat: 17.3200, lng: 78.5200, expected: 'vanasthali' },
  { name: 'Meerpet', lat: 17.3100, lng: 78.5100, expected: 'vanasthali' },
  
  # Residential Mixed
  { name: 'JNTU', lat: 17.4943, lng: 78.3941, expected: 'jntu_kukatpally' },
  { name: 'KPHB Colony', lat: 17.4830, lng: 78.3950, expected: 'jntu_kukatpally' },
  { name: 'Miyapur Metro', lat: 17.5100, lng: 78.3500, expected: 'miyapur' },
  { name: 'Chandanagar', lat: 17.4970, lng: 78.3370, expected: 'miyapur' },
  
  # Traditional Commercial
  { name: 'Charminar', lat: 17.3616, lng: 78.4747, expected: 'old_city' },
  { name: 'Nampally', lat: 17.3850, lng: 78.4700, expected: 'old_city' },
  { name: 'Koti', lat: 17.3800, lng: 78.4850, expected: 'tcs_synergy' },  # Near border
  
  # Growth Areas
  { name: 'Uppal Metro', lat: 17.4050, lng: 78.5600, expected: 'uppal_corridor' },
  { name: 'Kompally', lat: 17.5400, lng: 78.4800, expected: 'kompally' },
  
  # Airport
  { name: 'Shamshabad Airport', lat: 17.2403, lng: 78.4294, expected: 'outer_ring_south' },
]

def find_zone(lat, lng)
  # Use the new spatial-aware lookup
  Zone.find_containing('hyd', lat, lng) || 
    Zone.for_city('hyd').active.order(priority: :desc).find { |z| z.contains_point?(lat, lng) }
end

correct = 0
wrong = 0
no_zone = 0

KEY_LOCATIONS.each do |loc|
  zone = find_zone(loc[:lat], loc[:lng])
  actual = zone&.zone_code || 'NO_ZONE'
  
  if actual == 'NO_ZONE'
    status = '❌ NO ZONE'
    no_zone += 1
  elsif actual == loc[:expected]
    status = '✅ CORRECT'
    correct += 1
  else
    status = "⚠️  WRONG (expected: #{loc[:expected]})"
    wrong += 1
  end
  
  puts "#{status.ljust(35)} | #{loc[:name].ljust(25)} → #{actual}"
end

puts "-" * 100
puts "Results: ✅ #{correct} correct, ⚠️ #{wrong} wrong, ❌ #{no_zone} no zone"
puts "Accuracy: #{(correct.to_f / KEY_LOCATIONS.length * 100).round(1)}%"

# ============================================================================
# PART 3: GENERATE INTRA-ZONE TEST ROUTES (Same Zone Trips)
# ============================================================================
puts "\n\n🔵 INTRA-ZONE TEST ROUTES (Same Zone Trips):\n"
puts "-" * 100

INTRA_ZONE_ROUTES = [
  # hitech_madhapur (tech_corridor)
  { zone: 'hitech_madhapur', from: 'Cyber Towers', to: 'Inorbit Mall', 
    from_coords: [17.4504, 78.3810], to_coords: [17.4352, 78.3865], est_km: 2.5 },
  { zone: 'hitech_madhapur', from: 'Kondapur', to: 'Madhapur', 
    from_coords: [17.4600, 78.3700], to_coords: [17.4450, 78.3900], est_km: 3.0 },
  
  # fin_district (tech_corridor)
  { zone: 'fin_district', from: 'Raheja IT Park', to: 'Wipro Circle', 
    from_coords: [17.4293, 78.3370], to_coords: [17.4350, 78.3450], est_km: 1.5 },
  { zone: 'fin_district', from: 'ISB', to: 'Nanakramguda', 
    from_coords: [17.4189, 78.3423], to_coords: [17.4250, 78.3500], est_km: 2.0 },
  
  # ameerpet_core (business_cbd)
  { zone: 'ameerpet_core', from: 'Ameerpet Metro', to: 'SR Nagar', 
    from_coords: [17.4379, 78.4482], to_coords: [17.4400, 78.4400], est_km: 1.5 },
  
  # lb_nagar_east (residential_dense)
  { zone: 'lb_nagar_east', from: 'LB Nagar Metro', to: 'Saroornagar', 
    from_coords: [17.3515, 78.5530], to_coords: [17.3600, 78.5450], est_km: 1.8 },
  
  # vanasthali (residential_dense)
  { zone: 'vanasthali', from: 'Vanasthalipuram', to: 'Meerpet', 
    from_coords: [17.3200, 78.5200], to_coords: [17.3100, 78.5100], est_km: 2.0 },
  
  # jntu_kukatpally (residential_mixed)
  { zone: 'jntu_kukatpally', from: 'JNTU', to: 'KPHB Phase 1', 
    from_coords: [17.4943, 78.3941], to_coords: [17.4850, 78.3980], est_km: 1.5 },
  
  # old_city (traditional_commercial)
  { zone: 'old_city', from: 'Charminar', to: 'Nampally', 
    from_coords: [17.3616, 78.4747], to_coords: [17.3850, 78.4700], est_km: 3.0 },
  
  # secunderabad (business_cbd)
  { zone: 'secunderabad', from: 'Paradise', to: 'Secunderabad Railway', 
    from_coords: [17.4447, 78.4829], to_coords: [17.4339, 78.5011], est_km: 2.5 },
]

puts "| #{'Zone'.ljust(20)} | #{'From'.ljust(20)} | #{'To'.ljust(20)} | Est. Dist |"
puts "-" * 100

INTRA_ZONE_ROUTES.each do |r|
  from_zone = find_zone(r[:from_coords][0], r[:from_coords][1])
  to_zone = find_zone(r[:to_coords][0], r[:to_coords][1])
  
  valid = from_zone&.zone_code == r[:zone] && to_zone&.zone_code == r[:zone]
  status = valid ? '✅' : '❌'
  
  puts "#{status} #{r[:zone].ljust(18)} | #{r[:from].ljust(20)} | #{r[:to].ljust(20)} | #{r[:est_km]} km |"
end

# ============================================================================
# PART 4: GENERATE INTER-ZONE TEST ROUTES (Multiple Zone Trips)
# ============================================================================
puts "\n\n🟢 INTER-ZONE TEST ROUTES (Cross Zone Trips):\n"
puts "-" * 100

INTER_ZONE_ROUTES = [
  # Tech to Tech
  { from_zone: 'hitech_madhapur', to_zone: 'fin_district',
    from_name: 'Cyber Towers', to_name: 'Raheja IT Park',
    from_coords: [17.4504, 78.3810], to_coords: [17.4293, 78.3370], est_km: 5.0 },
  
  # Tech to CBD  
  { from_zone: 'fin_district', to_zone: 'ameerpet_core',
    from_name: 'ISB', to_name: 'Ameerpet Metro',
    from_coords: [17.4189, 78.3423], to_coords: [17.4379, 78.4482], est_km: 12.0 },
  
  { from_zone: 'hitech_madhapur', to_zone: 'secunderabad',
    from_name: 'Inorbit', to_name: 'Paradise Circle',
    from_coords: [17.4352, 78.3865], to_coords: [17.4447, 78.4829], est_km: 11.0 },
  
  # Residential to Tech
  { from_zone: 'lb_nagar_east', to_zone: 'tcs_synergy',
    from_name: 'LB Nagar Metro', to_name: 'TCS Synergy',
    from_coords: [17.3515, 78.5530], to_coords: [17.3817, 78.4801], est_km: 10.0 },
  
  { from_zone: 'jntu_kukatpally', to_zone: 'hitech_madhapur',
    from_name: 'JNTU', to_name: 'Cyber Towers',
    from_coords: [17.4943, 78.3941], to_coords: [17.4504, 78.3810], est_km: 6.0 },
  
  # Residential to CBD
  { from_zone: 'vanasthali', to_zone: 'old_city',
    from_name: 'Vanasthalipuram', to_name: 'Charminar',
    from_coords: [17.3200, 78.5200], to_coords: [17.3616, 78.4747], est_km: 8.0 },
  
  { from_zone: 'miyapur', to_zone: 'ameerpet_core',
    from_name: 'Miyapur Metro', to_name: 'Ameerpet',
    from_coords: [17.5100, 78.3500], to_coords: [17.4379, 78.4482], est_km: 14.0 },
  
  # CBD to CBD
  { from_zone: 'ameerpet_core', to_zone: 'secunderabad',
    from_name: 'Ameerpet', to_name: 'Secunderabad Railway',
    from_coords: [17.4379, 78.4482], to_coords: [17.4339, 78.5011], est_km: 6.0 },
  
  # Long Routes
  { from_zone: 'jntu_kukatpally', to_zone: 'old_city',
    from_name: 'JNTU', to_name: 'Charminar',
    from_coords: [17.4943, 78.3941], to_coords: [17.3616, 78.4747], est_km: 22.0 },
  
  { from_zone: 'kompally', to_zone: 'lb_nagar_east',
    from_name: 'Kompally', to_name: 'LB Nagar',
    from_coords: [17.5400, 78.4800], to_coords: [17.3515, 78.5530], est_km: 25.0 },
  
  # Airport Routes
  { from_zone: 'outer_ring_south', to_zone: 'hitech_madhapur',
    from_name: 'Airport', to_name: 'HITEC City',
    from_coords: [17.2403, 78.4294], to_coords: [17.4504, 78.3810], est_km: 28.0 },
  
  { from_zone: 'outer_ring_south', to_zone: 'secunderabad',
    from_name: 'Airport', to_name: 'Secunderabad',
    from_coords: [17.2403, 78.4294], to_coords: [17.4339, 78.5011], est_km: 32.0 },
]

puts "| #{'From Zone'.ljust(18)} | #{'To Zone'.ljust(18)} | #{'Route'.ljust(35)} | Est. km |"
puts "-" * 100

INTER_ZONE_ROUTES.each do |r|
  from_zone = find_zone(r[:from_coords][0], r[:from_coords][1])
  to_zone = find_zone(r[:to_coords][0], r[:to_coords][1])
  
  from_ok = from_zone&.zone_code == r[:from_zone]
  to_ok = to_zone&.zone_code == r[:to_zone]
  status = (from_ok && to_ok) ? '✅' : '❌'
  
  route_desc = "#{r[:from_name]} → #{r[:to_name]}"
  actual_from = from_ok ? r[:from_zone] : "#{from_zone&.zone_code || 'NONE'}"
  actual_to = to_ok ? r[:to_zone] : "#{to_zone&.zone_code || 'NONE'}"
  
  puts "#{status} #{actual_from.ljust(16)} | #{actual_to.ljust(18)} | #{route_desc.ljust(35)} | #{r[:est_km].to_s.rjust(5)} km |"
end

# ============================================================================
# PART 5: ZONE TYPE COVERAGE
# ============================================================================
puts "\n\n📊 ZONE TYPE COVERAGE:\n"
puts "-" * 60

zone_types = Zone.for_city('hyd').active.group(:zone_type).count
zone_types.each do |type, count|
  bar = '█' * count
  puts "#{type.ljust(25)} | #{count} zone(s) | #{bar}"
end

# ============================================================================
# SUMMARY
# ============================================================================
puts "\n" + "=" * 100
puts "📋 SUMMARY"
puts "=" * 100
puts "Total Zones: #{Zone.for_city('hyd').active.count}"
puts "Zone Types: #{zone_types.keys.join(', ')}"
puts "Location Accuracy: #{(correct.to_f / KEY_LOCATIONS.length * 100).round(1)}%"
puts "Intra-Zone Routes Ready: #{INTRA_ZONE_ROUTES.length}"
puts "Inter-Zone Routes Ready: #{INTER_ZONE_ROUTES.length}"
puts "=" * 100
