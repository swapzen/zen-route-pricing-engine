# frozen_string_literal: true

# Script to set up pricing configurations for all cities and vehicle types
# Based on Porter benchmark data and existing HYD configurations

puts "=" * 100
puts "🚀 SETTING UP PRICING CONFIGS FOR ALL CITIES"
puts "=" * 100

# Vehicle types from seeds.rb (Porter-aligned)
VEHICLE_TYPES = {
  'two_wheeler' => {
    vendor_code: '2W',
    capacity_kg: 20,
    display_name: '2 Wheeler',
    description: 'Bike delivery for small packages up to 20kg',
    base_fare_paise: 4500,
    base_distance_m: 1000,
    slabs: [
      [0,     3000,  350],
      [3000, 10000,  860],
      [10000, 25000, 1150],
      [25000, nil,    750]
    ]
  },
  'scooter' => {
    vendor_code: 'SCOOTER',
    capacity_kg: 20,
    display_name: 'Scooter',
    description: 'Scooter delivery for small packages up to 20kg',
    base_fare_paise: 6000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000,  450],
      [3000, 10000,  1100],
      [10000, 25000, 1400],
      [25000, nil,    900]
    ]
  },
  'mini_3w' => {
    vendor_code: 'MINI_3W',
    capacity_kg: 500,
    display_name: 'Mini 3W',
    description: 'Mini three-wheeler for medium packages up to 500kg',
    base_fare_paise: 10000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000,  900],
      [3000, 10000, 1265],
      [10000, 25000, 1000],
      [25000, nil,    750]
    ]
  },
  'three_wheeler' => {
    vendor_code: '3W',
    capacity_kg: 500,
    display_name: '3 Wheeler',
    description: 'Three-wheeler tempo for bulk goods up to 500kg',
    base_fare_paise: 20000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 2400],
      [3000, 10000, 3000],
      [10000, 25000, 2970],
      [25000, nil,   1900]
    ]
  },
  'three_wheeler_ev' => {
    vendor_code: '3W_EV',
    capacity_kg: 750,
    display_name: '3 Wheeler Electric',
    description: 'Eco-friendly electric three-wheeler up to 750kg',
    base_fare_paise: 18000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 1900],
      [3000, 10000, 2400],
      [10000, 25000, 2650],
      [25000, nil,   2000]
    ]
  },
  'tata_ace' => {
    vendor_code: 'TATA_ACE',
    capacity_kg: 750,
    display_name: 'Tata Ace',
    description: 'Mini truck for medium loads up to 750kg',
    base_fare_paise: 25000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 2600],
      [3000, 10000, 3200],
      [10000, 25000, 3080],
      [25000, nil,   2000]
    ]
  },
  'pickup_8ft' => {
    vendor_code: 'PICKUP_8FT',
    capacity_kg: 1250,
    display_name: 'Pickup 8ft',
    description: 'Pickup truck for large loads up to 1250kg',
    base_fare_paise: 30000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 3000],
      [3000, 10000, 3500],
      [10000, 25000, 3300],
      [25000, nil,   2150]
    ]
  },
  'eeco' => {
    vendor_code: 'EECO',
    capacity_kg: 500,
    display_name: 'Eeco Van',
    description: 'Maruti Eeco van for medium loads up to 500kg',
    base_fare_paise: 28000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 2300],
      [3000, 10000, 2600],
      [10000, 25000, 3100],
      [25000, nil,   2200]
    ]
  },
  'tata_407' => {
    vendor_code: 'TATA_407',
    capacity_kg: 2500,
    display_name: 'Tata 407',
    description: 'Large truck for heavy loads up to 2500kg',
    base_fare_paise: 85000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 2000],
      [3000, 10000, 2400],
      [10000, 25000, 3200],
      [25000, nil,   2600]
    ]
  },
  'canter_14ft' => {
    vendor_code: 'CANTER_14FT',
    capacity_kg: 3500,
    display_name: 'Canter 14ft',
    description: 'Extra heavy truck for bulk freight up to 3500kg',
    base_fare_paise: 145000,
    base_distance_m: 1000,
    slabs: [
      [0,     3000, 5000],
      [3000, 10000, 4600],
      [10000, 25000, 5200],
      [25000, nil,   3500]
    ]
  }
}.freeze

# Cities to set up
CITIES = [
  { code: 'HYD', name: 'Hyderabad', timezone: 'Asia/Kolkata' },
  { code: 'BLR', name: 'Bangalore', timezone: 'Asia/Kolkata' },
  { code: 'DEL', name: 'Delhi', timezone: 'Asia/Kolkata' },
  { code: 'MUM', name: 'Mumbai', timezone: 'Asia/Kolkata' }
].freeze

puts "\n💰 Creating pricing configs for all cities and vehicle types..."

CITIES.each do |city|
  puts "\n📍 #{city[:name]} (#{city[:code]})"
  
  VEHICLE_TYPES.each do |vehicle_type, config|
    # Check if config already exists
    existing = PricingConfig.current_version(city[:code], vehicle_type)
    
    if existing
      puts "   ⏭️  #{config[:display_name].ljust(20)} | Already exists (v#{existing.version})"
      next
    end
    
    # Create new pricing config
    pricing_config = PricingConfig.create!(
      city_code: city[:code].downcase,
      vehicle_type: vehicle_type,
      version: 1,
      timezone: city[:timezone],
      active: true,
      effective_from: Time.parse('2026-01-01 00:00:00 IST'),
      effective_until: nil,
      vendor_vehicle_code: config[:vendor_code],
      weight_capacity_kg: config[:capacity_kg],
      display_name: config[:display_name],
      description: config[:description],
      base_fare_paise: config[:base_fare_paise],
      min_fare_paise: config[:base_fare_paise],
      base_distance_m: config[:base_distance_m],
      per_km_rate_paise: 0,  # Using slab pricing
      vehicle_multiplier: 1.0,
      city_multiplier: 1.0,
      surge_multiplier: 1.0,
      variance_buffer_pct: 0.0,
      min_margin_pct: 0.0
    )
    
    # Create distance slabs
    config[:slabs].each do |slab|
      PricingDistanceSlab.create!(
        pricing_config: pricing_config,
        min_distance_m: slab[0],
        max_distance_m: slab[1],
        per_km_rate_paise: slab[2]
      )
    end
    
    # Create surge rules (same as HYD)
    PricingSurgeRule.create!(
      pricing_config_id: pricing_config.id,
      rule_type: 'time_of_day',
      condition_json: { start_hour: 8, end_hour: 10, days: ['Mon','Tue','Wed','Thu','Fri'] },
      multiplier: 1.08, priority: 100, active: true, notes: 'Morning Rush'
    )
    PricingSurgeRule.create!(
      pricing_config_id: pricing_config.id,
      rule_type: 'time_of_day',
      condition_json: { start_hour: 18, end_hour: 21, days: ['Mon','Tue','Wed','Thu','Fri'] },
      multiplier: 1.10, priority: 100, active: true, notes: 'Evening Rush'
    )
    PricingSurgeRule.create!(
      pricing_config_id: pricing_config.id,
      rule_type: 'time_of_day',
      condition_json: { start_hour: 0, end_hour: 24, days: ['Sat'] },
      multiplier: 0.95, priority: 50, active: true, notes: 'Sat Discount'
    )
    PricingSurgeRule.create!(
      pricing_config_id: pricing_config.id,
      rule_type: 'time_of_day',
      condition_json: { start_hour: 0, end_hour: 24, days: ['Sun'] },
      multiplier: 0.92, priority: 50, active: true, notes: 'Sun Discount'
    )
    
    puts "   ✅ #{config[:display_name].ljust(20)} | Base ₹#{(config[:base_fare_paise]/100).to_s.rjust(5)} | Created"
  end
end

puts "\n" + "=" * 100
puts "🎉 COMPLETE!"
puts "=" * 100

# Summary
CITIES.each do |city|
  count = PricingConfig.where('LOWER(city_code) = LOWER(?)', city[:code])
                      .where(active: true, effective_until: nil)
                      .where('effective_from <= ?', Time.current)
                      .count
  puts "   #{city[:name]}: #{count} active pricing configs"
end

puts "\nTotal vehicle types: #{VEHICLE_TYPES.count}"
puts "Total cities: #{CITIES.count}"
puts "Expected total configs: #{VEHICLE_TYPES.count * CITIES.count}"
