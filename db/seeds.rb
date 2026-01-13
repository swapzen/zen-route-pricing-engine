# frozen_string_literal: true

puts "🌱 Starting Zen Route Pricing Engine seed data..."

# =============================================================================
# PRICING CONFIGS & SURGE RULES (Hyderabad - 3 Vehicle Types)
# =============================================================================
puts "💰 Creating pricing configs and surge rules..."

# Two-Wheeler Config
two_wheeler_config = PricingConfig.find_or_create_by(
  city_code: 'hyd',
  vehicle_type: 'two_wheeler',
  version: 1,
  effective_until: nil
) do |config|
  config.timezone = 'Asia/Kolkata'
  config.base_fare_paise = 2000
  config.min_fare_paise = 2000
  config.base_distance_m = 2000
  config.per_km_rate_paise = 800
  config.vehicle_multiplier = 1.0
  config.city_multiplier = 1.0
  config.surge_multiplier = 1.0
  config.variance_buffer_pct = 0.05
  config.variance_buffer_min_paise = 500
  config.variance_buffer_max_paise = 2000
  config.high_value_threshold_paise = 0
  config.high_value_buffer_pct = 0.0
  config.high_value_buffer_min_paise = 0
  config.min_margin_pct = 0.03
  config.min_margin_flat_paise = 1000
  config.active = true
  config.effective_from = Time.parse('2026-01-01 00:00:00 IST')
  config.notes = 'Initial v1 config for Hyderabad two-wheeler'
end

# Surge rules for two_wheeler
if two_wheeler_config
  PricingSurgeRule.find_or_create_by(
    pricing_config_id: two_wheeler_config.id,
    rule_type: 'time_of_day',
    condition_json: { start_hour: 8, end_hour: 10, days: ['Mon','Tue','Wed','Thu','Fri'] }
  ) do |rule|
    rule.multiplier = 1.2
    rule.priority = 100
    rule.active = true
    rule.notes = 'Morning rush hour surge'
  end

  PricingSurgeRule.find_or_create_by(
    pricing_config_id: two_wheeler_config.id,
    rule_type: 'time_of_day',
    condition_json: { start_hour: 18, end_hour: 20, days: ['Mon','Tue','Wed','Thu','Fri'] }
  ) do |rule|
    rule.multiplier = 1.25
    rule.priority = 100
    rule.active = true
    rule.notes = 'Evening rush hour surge (higher than morning)' 
  end

  PricingSurgeRule.find_or_create_by(
    pricing_config_id: two_wheeler_config.id,
    rule_type: 'traffic_level',
    condition_json: { min_duration_ratio: 1.3 }
  ) do |rule|
    rule.multiplier = 1.15
    rule.priority = 90
    rule.active = true
    rule.notes = 'Heavy traffic surge'
  end
end

# Three-Wheeler Config
three_wheeler_config = PricingConfig.find_or_create_by(
  city_code: 'hyd',
  vehicle_type: 'three_wheeler',
  version: 1,
  effective_until: nil
) do |config|
  config.timezone = 'Asia/Kolkata'
  config.base_fare_paise = 10000
  config.min_fare_paise = 10000
  config.base_distance_m = 2000
  config.per_km_rate_paise = 1200
  config.vehicle_multiplier = 1.0
  config.city_multiplier = 1.0
  config.surge_multiplier = 1.0
  config.variance_buffer_pct = 0.06
  config.variance_buffer_min_paise = 800
  config.variance_buffer_max_paise = 3000
  config.high_value_threshold_paise = 0
  config.high_value_buffer_pct = 0.0
  config.high_value_buffer_min_paise = 0
  config.min_margin_pct = 0.035
  config.min_margin_flat_paise = 2000
  config.active = true
  config.effective_from = Time.parse('2026-01-01 00:00:00 IST')
  config.notes = 'Initial v1 config for Hyderabad three-wheeler'
end

# Four-Wheeler Config
four_wheeler_config = PricingConfig.find_or_create_by(
  city_code: 'hyd',
  vehicle_type: 'four_wheeler',
  version: 1,
  effective_until: nil
) do |config|
  config.timezone = 'Asia/Kolkata'
  config.base_fare_paise = 20000
  config.min_fare_paise = 20000
  config.base_distance_m = 2000
  config.per_km_rate_paise = 2000
  config.vehicle_multiplier = 1.0
  config.city_multiplier = 1.0
  config.surge_multiplier = 1.0
  config.variance_buffer_pct = 0.08
  config.variance_buffer_min_paise = 1000
  config.variance_buffer_max_paise = 5000
  config.high_value_threshold_paise = 0
  config.high_value_buffer_pct = 0.0
  config.high_value_buffer_min_paise = 0
  config.min_margin_pct = 0.04
  config.min_margin_flat_paise = 3000
  config.active = true
  config.effective_from = Time.parse('2026-01-01 00:00:00 IST')
  config.notes = 'Initial v1 config for Hyderabad four-wheeler'
end

puts "✅ Created #{PricingConfig.count} pricing configs"
puts "✅ Created #{PricingSurgeRule.count} surge rules"

puts "\n🎉 SEED DATA CREATION COMPLETE!"
puts "=" * 50
puts "💰 Pricing Configs: #{PricingConfig.count}"
puts "🔥 Surge Rules: #{PricingSurgeRule.count}"
puts "=" * 50
puts "✅ Ready for API testing!"
