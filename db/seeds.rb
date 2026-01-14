# frozen_string_literal: true

puts "🌱 Starting Zen Route Pricing Engine seed data..."

# =============================================================================
# VEHICLE TYPE DEFINITIONS
# =============================================================================
# Pricing tuned to be 3-5% ABOVE market rates (vendor margin protection)
# SwapZen price > Market price always (we pay vendor, customer pays us)
#
# Formula: Market Price + 3-5% margin = SwapZen Price
# For 21.6km route (DispatchTrack → Charminar benchmark)

VEHICLE_TYPES = {
  'two_wheeler' => {
    vendor_code: '2W',
    capacity_kg: 20,
    display_name: '2 Wheeler',
    description: 'Bike delivery for small packages up to 20kg',
    # Market: ₹218 → Target: ₹228 (+5%)
    base_fare_paise: 2500,      # ₹25
    per_km_rate_paise: 900,     # ₹9/km
    variance_buffer_pct: 0.05,
    min_margin_pct: 0.03
  },
  'scooter' => {
    vendor_code: 'SCOOTER',
    capacity_kg: 20,
    display_name: 'Scooter',
    description: 'Scooter delivery for small packages up to 20kg',
    # Market: ₹272 → Target: ₹285 (+5%)
    base_fare_paise: 3500,      # ₹35
    per_km_rate_paise: 1150,    # ₹11.50/km
    variance_buffer_pct: 0.05,
    min_margin_pct: 0.03
  },
  'mini_3w' => {
    vendor_code: 'MINI_3W',
    capacity_kg: 50,
    display_name: 'Mini 3W',
    description: 'Mini three-wheeler for medium packages up to 50kg',
    # Market: ₹338 → Target: ₹355 (+5%)
    base_fare_paise: 11500,     # ₹115
    per_km_rate_paise: 1050,    # ₹10.50/km
    variance_buffer_pct: 0.05,
    min_margin_pct: 0.03
  },
  'three_wheeler' => {
    vendor_code: '3W',
    capacity_kg: 500,
    display_name: '3 Wheeler',
    description: 'Three-wheeler tempo for bulk goods up to 500kg',
    # Market: ₹813 → Target: ₹850 (+5%)
    base_fare_paise: 38000,     # ₹380
    per_km_rate_paise: 2100,    # ₹21/km
    variance_buffer_pct: 0.04,
    min_margin_pct: 0.03
  },
  'three_wheeler_ev' => {
    vendor_code: '3W_EV',
    capacity_kg: 750,
    display_name: '3 Wheeler Electric',
    description: 'Eco-friendly electric three-wheeler up to 750kg',
    # Market: ₹800 → Target: ₹840 (+5%)
    base_fare_paise: 37000,     # ₹370
    per_km_rate_paise: 2100,    # ₹21/km
    variance_buffer_pct: 0.04,
    min_margin_pct: 0.03
  },
  'tata_ace' => {
    vendor_code: 'TATA_ACE',
    capacity_kg: 750,
    display_name: 'Tata Ace',
    description: 'Mini truck for medium loads up to 750kg',
    # Market: ₹856 → Target: ₹900 (+5%)
    base_fare_paise: 40000,     # ₹400
    per_km_rate_paise: 2200,    # ₹22/km
    variance_buffer_pct: 0.04,
    min_margin_pct: 0.03
  },
  'pickup_8ft' => {
    vendor_code: 'PICKUP_8FT',
    capacity_kg: 1250,
    display_name: 'Pickup 8ft',
    description: 'Pickup truck for large loads up to 1250kg',
    # Market: ₹929 → Target: ₹975 (+5%)
    base_fare_paise: 43000,     # ₹430
    per_km_rate_paise: 2400,    # ₹24/km
    variance_buffer_pct: 0.04,
    min_margin_pct: 0.03
  },
  'eeco' => {
    vendor_code: 'EECO',
    capacity_kg: 500,
    display_name: 'Eeco Van',
    description: 'Maruti Eeco van for medium loads up to 500kg',
    # Market: ₹900 → Target: ₹945 (+5%)
    base_fare_paise: 41000,     # ₹410
    per_km_rate_paise: 2350,    # ₹23.50/km
    variance_buffer_pct: 0.04,
    min_margin_pct: 0.03
  },
  'tata_407' => {
    vendor_code: 'TATA_407',
    capacity_kg: 2500,
    display_name: 'Tata 407',
    description: 'Large truck for heavy loads up to 2500kg',
    # Market: ₹1400 → Target: ₹1470 (+5%)
    base_fare_paise: 65000,     # ₹650
    per_km_rate_paise: 3700,    # ₹37/km
    variance_buffer_pct: 0.04,
    min_margin_pct: 0.03
  },
  'canter_14ft' => {
    vendor_code: 'CANTER_14FT',
    capacity_kg: 3500,
    display_name: 'Canter 14ft',
    description: 'Extra heavy truck for bulk freight up to 3500kg',
    # Market: ₹2200 → Target: ₹2300 (+5%)
    base_fare_paise: 105000,    # ₹1050
    per_km_rate_paise: 5800,    # ₹58/km
    variance_buffer_pct: 0.03,
    min_margin_pct: 0.02
  }
}.freeze

# =============================================================================
# PRICING CONFIGS (Hyderabad - All Vehicle Types)
# =============================================================================
puts "💰 Creating pricing configs for all vehicle types..."
puts "   (Priced 3-5% ABOVE market for vendor margin protection)"
puts

VEHICLE_TYPES.each do |vehicle_type, config|
  pricing_config = PricingConfig.find_or_create_by(
    city_code: 'hyd',
    vehicle_type: vehicle_type,
    version: 1,
    effective_until: nil
  ) do |c|
    c.timezone = 'Asia/Kolkata'
    c.base_fare_paise = config[:base_fare_paise]
    c.min_fare_paise = config[:base_fare_paise]
    c.base_distance_m = 2000  # 2km included
    c.per_km_rate_paise = config[:per_km_rate_paise]
    c.vehicle_multiplier = 1.0
    c.city_multiplier = 1.0
    c.surge_multiplier = 1.0
    c.variance_buffer_pct = config[:variance_buffer_pct]
    c.variance_buffer_min_paise = 500
    c.variance_buffer_max_paise = (config[:base_fare_paise] * 0.5).to_i
    c.high_value_threshold_paise = 0
    c.high_value_buffer_pct = 0.0
    c.high_value_buffer_min_paise = 0
    c.min_margin_pct = config[:min_margin_pct]
    c.min_margin_flat_paise = 1000
    c.active = true
    c.effective_from = Time.parse('2026-01-01 00:00:00 IST')
    c.notes = "Market-tuned pricing for #{config[:display_name]} (+5% margin)"
    
    # Vehicle metadata
    c.vendor_vehicle_code = config[:vendor_code]
    c.weight_capacity_kg = config[:capacity_kg]
    c.display_name = config[:display_name]
    c.description = config[:description]
  end

  # Update existing records
  pricing_config.update!(
    base_fare_paise: config[:base_fare_paise],
    per_km_rate_paise: config[:per_km_rate_paise],
    variance_buffer_pct: config[:variance_buffer_pct],
    variance_buffer_max_paise: (config[:base_fare_paise] * 0.5).to_i,
    min_margin_pct: config[:min_margin_pct],
    vendor_vehicle_code: config[:vendor_code],
    weight_capacity_kg: config[:capacity_kg],
    display_name: config[:display_name],
    description: config[:description]
  )

  puts "   ✅ #{config[:display_name].ljust(20)} | Base ₹#{(config[:base_fare_paise]/100).to_s.rjust(6)} + ₹#{(config[:per_km_rate_paise]/100.0).to_s.rjust(5)}/km"
end

# =============================================================================
# SURGE RULES
# =============================================================================
puts "\n🔥 Creating surge rules..."

surge_vehicles = ['two_wheeler', 'three_wheeler', 'tata_ace']

surge_vehicles.each do |vehicle_type|
  config = PricingConfig.find_by(city_code: 'hyd', vehicle_type: vehicle_type, active: true)
  next unless config

  PricingSurgeRule.find_or_create_by(
    pricing_config_id: config.id,
    rule_type: 'time_of_day',
    condition_json: { start_hour: 8, end_hour: 10, days: ['Mon','Tue','Wed','Thu','Fri'] }
  ) do |rule|
    rule.multiplier = 1.2
    rule.priority = 100
    rule.active = true
    rule.notes = 'Morning rush hour surge'
  end

  PricingSurgeRule.find_or_create_by(
    pricing_config_id: config.id,
    rule_type: 'time_of_day',
    condition_json: { start_hour: 18, end_hour: 20, days: ['Mon','Tue','Wed','Thu','Fri'] }
  ) do |rule|
    rule.multiplier = 1.25
    rule.priority = 100
    rule.active = true
    rule.notes = 'Evening rush hour surge'
  end

  PricingSurgeRule.find_or_create_by(
    pricing_config_id: config.id,
    rule_type: 'traffic_level',
    condition_json: { min_duration_ratio: 1.3 }
  ) do |rule|
    rule.multiplier = 1.15
    rule.priority = 90
    rule.active = true
    rule.notes = 'Heavy traffic surge'
  end
end

puts "   ✅ Created surge rules for #{surge_vehicles.join(', ')}"

# =============================================================================
# SUMMARY
# =============================================================================
puts "\n🎉 SEED DATA CREATION COMPLETE!"
puts "=" * 70
puts "💰 Pricing Configs: #{PricingConfig.count}"
puts "🔥 Surge Rules: #{PricingSurgeRule.count}"
puts "\n📊 Vehicle Types (Hyderabad) - Priced 3-5% ABOVE market:"
puts "-" * 70
printf("   %-20s | %6s | %10s | %10s\n", "Vehicle", "Cap", "Base Fare", "Per KM")
puts "-" * 70
PricingConfig.where(city_code: 'hyd', active: true).order(:base_fare_paise).each do |c|
  printf("   %-20s | %5dkg | ₹%8.0f | ₹%8.1f\n", 
         c.display_name, c.weight_capacity_kg, c.base_fare_paise/100.0, c.per_km_rate_paise/100.0)
end
puts "=" * 70
puts "✅ Ready for API testing!"
