# frozen_string_literal: true
# Generate test coordinates for intra-zone and inter-zone routes

puts "=" * 80
puts "== GENERATING TEST ROUTES FOR ALL ZONES =="
puts "=" * 80

# Known coordinates within each zone (from real Hyderabad locations)
ZONE_COORDINATES = {
  'hitech_madhapur' => {
    name: 'HITEC City / Madhapur',
    places: [
      { name: 'Cyber Towers', lat: 17.4504, lng: 78.3810 },
      { name: 'Inorbit Mall', lat: 17.4355, lng: 78.3855 },
      { name: 'Mind Space', lat: 17.4400, lng: 78.3750 }
    ]
  },
  'fin_district' => {
    name: 'Financial District / Gachibowli',
    places: [
      { name: 'Raheja IT Park', lat: 17.4293, lng: 78.3370 },
      { name: 'Salarpuria Sattva', lat: 17.4230, lng: 78.3400 },
      { name: 'DLF Cyber City', lat: 17.4350, lng: 78.3500 }
    ]
  },
  'tcs_synergy' => {
    name: 'TCS Synergy Park Area',
    places: [
      { name: 'TCS Synergy', lat: 17.3817, lng: 78.4801 },
      { name: 'TSIIC IT Park', lat: 17.3850, lng: 78.4750 }
    ]
  },
  'lb_nagar_east' => {
    name: 'LB Nagar / Dilsukhnagar',
    places: [
      { name: 'LB Nagar Metro', lat: 17.3515, lng: 78.5530 },
      { name: 'Shantiniketan', lat: 17.3480, lng: 78.5450 },
      { name: 'Kothapet Junction', lat: 17.3600, lng: 78.5400 }
    ]
  },
  'vanasthali' => {
    name: 'Vanasthali Puram',
    places: [
      { name: 'Vanasthali Hills', lat: 17.3300, lng: 78.5200 },
      { name: 'Vanasthali Main', lat: 17.3250, lng: 78.5100 }
    ]
  },
  'ameerpet_core' => {
    name: 'Ameerpet Metro Area',
    places: [
      { name: 'Ameerpet Metro', lat: 17.4379, lng: 78.4482 },
      { name: 'SR Nagar', lat: 17.4400, lng: 78.4400 }
    ]
  },
  'ameerpet_extended' => {
    name: 'Ameerpet Extended',
    places: [
      { name: 'Panjagutta', lat: 17.4300, lng: 78.4550 },
      { name: 'Yousufguda', lat: 17.4250, lng: 78.4600 }
    ]
  },
  'jntu_kukatpally' => {
    name: 'JNTU / Kukatpally',
    places: [
      { name: 'JNTU Main Gate', lat: 17.4943, lng: 78.3941 },
      { name: 'Kukatpally Housing Board', lat: 17.4850, lng: 78.4000 }
    ]
  },
  'nexus_kukatpally' => {
    name: 'Nexus / Forum Mall Area',
    places: [
      { name: 'Forum Mall', lat: 17.4890, lng: 78.4210 },
      { name: 'Nexus Mall', lat: 17.4850, lng: 78.4150 }
    ]
  },
  'charminar_extended' => {
    name: 'Charminar / Old City Edge',
    places: [
      { name: 'Charminar', lat: 17.3616, lng: 78.4747 },
      { name: 'Mecca Masjid', lat: 17.3600, lng: 78.4730 }
    ]
  },
  'old_city' => {
    name: 'Old City Center',
    places: [
      { name: 'Nampally', lat: 17.3850, lng: 78.4700 },
      { name: 'Abids', lat: 17.3900, lng: 78.4750 }
    ]
  },
  'uppal_corridor' => {
    name: 'Uppal / ECIL',
    places: [
      { name: 'Uppal Metro', lat: 17.4050, lng: 78.5600 },
      { name: 'ECIL Crossroads', lat: 17.4100, lng: 78.5550 }
    ]
  },
  'outer_ring' => {
    name: 'ORR / Airport Area',
    places: [
      { name: 'Shamshabad Airport', lat: 17.2403, lng: 78.4294 },
      { name: 'ORR Exit 18', lat: 17.2800, lng: 78.4000 }
    ]
  }
}

def find_zone(city_code, lat, lng)
  Zone.for_city(city_code).active.order(priority: :desc).find { |z| z.contains_point?(lat, lng) }
end

puts "\n" + "=" * 80
puts "== VALIDATING ZONE COORDINATES =="
puts "=" * 80

puts "\n📍 Checking which zone each coordinate maps to:\n"

ZONE_COORDINATES.each do |expected_zone, data|
  puts "\n#{data[:name]} (expected: #{expected_zone}):"
  data[:places].each do |place|
    actual_zone = find_zone('hyd', place[:lat], place[:lng])
    status = actual_zone&.zone_code == expected_zone ? '✅' : '❌'
    actual = actual_zone&.zone_code || 'NO_ZONE'
    puts "  #{status} #{place[:name]}: (#{place[:lat]}, #{place[:lng]}) → #{actual}"
  end
end

puts "\n" + "=" * 80
puts "== LIST 1: INTRA-ZONE TEST ROUTES (Same Zone) =="
puts "=" * 80

puts "\nThese routes test zone time pricing (morning/afternoon/evening bands):\n"

ZONE_COORDINATES.each do |zone_code, data|
  next if data[:places].length < 2
  
  p1 = data[:places][0]
  p2 = data[:places][1]
  
  zone1 = find_zone('hyd', p1[:lat], p1[:lng])
  zone2 = find_zone('hyd', p2[:lat], p2[:lng])
  
  if zone1 && zone2 && zone1.zone_code == zone2.zone_code
    puts "\n🔵 INTRA-#{zone_code.upcase}:"
    puts "   From: #{p1[:name]} (#{p1[:lat]}, #{p1[:lng]})"
    puts "   To:   #{p2[:name]} (#{p2[:lat]}, #{p2[:lng]})"
    puts "   Zone: #{zone1.zone_code} (#{zone1.zone_type})"
  else
    puts "\n⚠️ #{zone_code}: Points map to different zones!"
    puts "   #{p1[:name]} → #{zone1&.zone_code || 'NONE'}"
    puts "   #{p2[:name]} → #{zone2&.zone_code || 'NONE'}"
  end
end

puts "\n" + "=" * 80
puts "== LIST 2: INTER-ZONE TEST ROUTES (Different Zones) =="
puts "=" * 80

puts "\nThese routes test corridor pricing (if exists) or origin zone pricing:\n"

# Key inter-zone routes covering different zone types
INTER_ZONE_ROUTES = [
  # Tech corridor ↔ Tech corridor
  { from: 'hitech_madhapur', to: 'fin_district', desc: 'Tech → Tech (corridor exists)' },
  { from: 'fin_district', to: 'hitech_madhapur', desc: 'Tech → Tech (corridor exists)' },
  { from: 'fin_district', to: 'tcs_synergy', desc: 'Tech → Tech (no corridor)' },
  
  # Tech ↔ CBD
  { from: 'fin_district', to: 'ameerpet_core', desc: 'Tech → CBD (corridor exists)' },
  { from: 'hitech_madhapur', to: 'ameerpet_core', desc: 'Tech → CBD (no corridor)' },
  
  # Tech ↔ Residential
  { from: 'lb_nagar_east', to: 'tcs_synergy', desc: 'Residential → Tech (corridor exists)' },
  { from: 'hitech_madhapur', to: 'lb_nagar_east', desc: 'Tech → Residential (no corridor)' },
  
  # Residential ↔ Residential
  { from: 'vanasthali', to: 'lb_nagar_east', desc: 'Residential → Residential' },
  { from: 'jntu_kukatpally', to: 'vanasthali', desc: 'Mixed → Dense' },
  
  # CBD ↔ Traditional Commercial
  { from: 'ameerpet_core', to: 'nexus_kukatpally', desc: 'CBD → Mall (corridor exists)' },
  { from: 'jntu_kukatpally', to: 'charminar_extended', desc: 'Mixed → Traditional (corridor exists)' },
  { from: 'vanasthali', to: 'charminar_extended', desc: 'Residential → Traditional (corridor exists)' },
  
  # Outer area routes
  { from: 'outer_ring', to: 'hitech_madhapur', desc: 'Airport → Tech' },
  { from: 'uppal_corridor', to: 'lb_nagar_east', desc: 'Growth → Residential' }
]

INTER_ZONE_ROUTES.each do |route|
  from_data = ZONE_COORDINATES[route[:from]]
  to_data = ZONE_COORDINATES[route[:to]]
  
  next unless from_data && to_data
  
  from_place = from_data[:places].first
  to_place = to_data[:places].first
  
  from_zone = find_zone('hyd', from_place[:lat], from_place[:lng])
  to_zone = find_zone('hyd', to_place[:lat], to_place[:lng])
  
  # Check if corridor exists
  corridor = nil
  if from_zone && to_zone
    corridor = ZonePairVehiclePricing.find_by(
      city_code: 'hyd',
      from_zone_id: from_zone.id,
      to_zone_id: to_zone.id,
      vehicle_type: 'two_wheeler',
      active: true
    )
  end
  
  pricing_type = corridor ? "CORRIDOR (base=₹#{corridor.base_fare_paise/100.0})" : "ZONE (#{from_zone&.zone_code})"
  
  puts "\n🟢 #{route[:desc]}:"
  puts "   From: #{from_place[:name]} (#{from_place[:lat]}, #{from_place[:lng]}) [#{from_zone&.zone_code || 'NONE'}]"
  puts "   To:   #{to_place[:name]} (#{to_place[:lat]}, #{to_place[:lng]}) [#{to_zone&.zone_code || 'NONE'}]"
  puts "   Pricing: #{pricing_type}"
end

puts "\n" + "=" * 80
puts "✅ Route generation complete!"
puts "=" * 80
