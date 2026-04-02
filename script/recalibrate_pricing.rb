# frozen_string_literal: true

# =============================================================================
# PRICING RECALIBRATION SCRIPT — 2026 Market Rates
# =============================================================================
# Recalibrates all pricing to 2026 Porter benchmarks + 7% SwapZen markup.
# Corridors are deactivated — inter-zone formula (Tier 2) handles cross-zone.
#
# Target: 5-10% margin over Porter's vendor rates across all vehicle types.
#
# USAGE:
#   RAILS_ENV=development bundle exec ruby script/recalibrate_pricing.rb
# =============================================================================

require_relative '../config/environment'

# =============================================================================
# 2026 PORTER BENCHMARK RATES (April 2026, Hyderabad, in paise)
# =============================================================================
PORTER_RATES = {
  'two_wheeler'      => { base: 4800,   per_km: 1400, free_km_m: 1000 },
  'scooter'          => { base: 6000,   per_km: 1500, free_km_m: 1000 },
  'mini_3w'          => { base: 10000,  per_km: 1200, free_km_m: 1000 },
  'three_wheeler'    => { base: 16100,  per_km: 1800, free_km_m: 1000 },
  'three_wheeler_ev' => { base: 16100,  per_km: 1800, free_km_m: 1000 },
  'tata_ace'         => { base: 21800,  per_km: 2000, free_km_m: 2000 },
  'pickup_8ft'       => { base: 31800,  per_km: 2500, free_km_m: 1000 },
  'eeco'             => { base: 35000,  per_km: 3200, free_km_m: 1000 },
  'tata_407'         => { base: 55100,  per_km: 4200, free_km_m: 2000 },
  'canter_14ft'      => { base: 150000, per_km: 5500, free_km_m: 2000 }
}.freeze

# Target: 5-10% over Porter (7% average)
MARKUP = 1.07

# Per-km rate bounds (in paise) by vehicle type — 2026 calibrated
PER_KM_BOUNDS = {
  'two_wheeler'      => { min: 1200, max: 1900, target: 1500 },
  'scooter'          => { min: 1300, max: 2000, target: 1600 },
  'mini_3w'          => { min: 1000, max: 1700, target: 1300 },
  'three_wheeler'    => { min: 1500, max: 2400, target: 1900 },
  'three_wheeler_ev' => { min: 1500, max: 2400, target: 1900 },
  'tata_ace'         => { min: 1700, max: 2700, target: 2100 },
  'pickup_8ft'       => { min: 2200, max: 3400, target: 2700 },
  'eeco'             => { min: 2800, max: 4200, target: 3400 },
  'tata_407'         => { min: 3600, max: 5600, target: 4500 },
  'canter_14ft'      => { min: 4800, max: 7400, target: 5900 }
}.freeze

# Zone type multipliers for per_km rate adjustment
ZONE_TYPE_RATE_MULT = {
  'tech_corridor'          => 1.00,
  'business_cbd'           => 1.05,
  'residential_dense'      => 1.00,
  'residential_mixed'      => 0.95,
  'residential_growth'     => 0.90,
  'premium_residential'    => 1.08,
  'airport_logistics'      => 1.08,
  'industrial'             => 0.95,
  'outer_ring'             => 0.88,
  'traditional_commercial' => 1.05,
  'heritage_commercial'    => 1.03,
  'default'                => 1.00
}.freeze

# 8-band time multipliers
TIME_BAND_MULT = {
  'early_morning' => 0.92,
  'morning_rush'  => 1.00,
  'midday'        => 0.95,
  'afternoon'     => 1.00,
  'evening_rush'  => 1.12,
  'night'         => 1.00,
  'weekend_day'   => 0.95,
  'weekend_night' => 0.90
}.freeze

puts "=" * 80
puts "PRICING RECALIBRATION — 2026 Market Rates"
puts "=" * 80
puts

# =============================================================================
# STEP 1: Fix city default PricingConfig
# =============================================================================
puts "-" * 80
puts "STEP 1: Fix city default PricingConfig"
puts "-" * 80

updated_configs = 0
PricingConfig.where(city_code: 'hyd', active: true).each do |config|
  porter = PORTER_RATES[config.vehicle_type]
  next unless porter

  bounds = PER_KM_BOUNDS[config.vehicle_type]
  new_base = (porter[:base] * MARKUP).round
  new_per_km = bounds[:target]
  new_min_fare = new_base
  new_base_distance = porter[:free_km_m]
  new_per_min = (porter[:per_km] * 0.10).round # ~10% of per_km as per-min rate

  old_vals = "base=#{config.base_fare_paise} per_km=#{config.per_km_rate_paise} min=#{config.min_fare_paise} base_dist=#{config.base_distance_m}"
  new_vals = "base=#{new_base} per_km=#{new_per_km} min=#{new_min_fare} base_dist=#{new_base_distance}"

  config.update!(
    base_fare_paise: new_base,
    per_km_rate_paise: new_per_km,
    min_fare_paise: new_min_fare,
    base_distance_m: new_base_distance,
    per_min_rate_paise: new_per_min
  )

  puts "  #{config.vehicle_type}: #{old_vals} -> #{new_vals}"
  updated_configs += 1
end
puts "  Updated #{updated_configs} city default configs"
puts

# =============================================================================
# STEP 2: Fix zone_vehicle_pricing per_km rates
# =============================================================================
puts "-" * 80
puts "STEP 2: Fix zone_vehicle_pricing per_km rate outliers"
puts "-" * 80

zvp_fixed = 0
zvp_filled = 0

ZoneVehiclePricing.where(active: true).includes(:zone).each do |zvp|
  zone = zvp.zone
  next unless zone

  bounds = PER_KM_BOUNDS[zvp.vehicle_type]
  next unless bounds

  zone_mult = ZONE_TYPE_RATE_MULT[zone.zone_type] || ZONE_TYPE_RATE_MULT['default']
  target_rate = (bounds[:target] * zone_mult).round
  max_rate = (bounds[:max] * 1.10).round  # Allow 10% above max for premium zones
  min_rate = (bounds[:min] * 0.90).round  # Allow 10% below min for growth zones

  old_per_km = zvp.per_km_rate_paise

  if old_per_km == 0
    zvp.update!(per_km_rate_paise: target_rate)
    puts "  FILL #{zone.zone_code}/#{zvp.vehicle_type}: 0 -> #{target_rate}"
    zvp_filled += 1
  elsif old_per_km > max_rate
    zvp.update!(per_km_rate_paise: target_rate)
    puts "  CAP  #{zone.zone_code}/#{zvp.vehicle_type}: #{old_per_km} -> #{target_rate}"
    zvp_fixed += 1
  elsif old_per_km < min_rate
    zvp.update!(per_km_rate_paise: target_rate)
    puts "  RAISE #{zone.zone_code}/#{zvp.vehicle_type}: #{old_per_km} -> #{target_rate}"
    zvp_fixed += 1
  end
end
puts "  Fixed #{zvp_fixed} outliers, filled #{zvp_filled} zeros"
puts

# =============================================================================
# STEP 3: Fix zone_vehicle_time_pricing per_km rates
# =============================================================================
puts "-" * 80
puts "STEP 3: Fix zone_vehicle_time_pricing per_km rate outliers"
puts "-" * 80

zvtp_fixed = 0
zvtp_filled = 0

ZoneVehicleTimePricing.where(active: true).each do |zvtp|
  zvp = ZoneVehiclePricing.find_by(id: zvtp.zone_vehicle_pricing_id)
  next unless zvp

  zone = Zone.find_by(id: zvp.zone_id)
  next unless zone

  bounds = PER_KM_BOUNDS[zvp.vehicle_type]
  next unless bounds

  zone_mult = ZONE_TYPE_RATE_MULT[zone.zone_type] || ZONE_TYPE_RATE_MULT['default']
  time_mult = TIME_BAND_MULT[zvtp.time_band] || 1.0
  target_rate = (bounds[:target] * zone_mult * time_mult).round
  max_rate = (bounds[:max] * 1.10 * time_mult).round
  min_rate = (bounds[:min] * 0.90).round

  old_per_km = zvtp.per_km_rate_paise

  if old_per_km == 0
    zvtp.update!(per_km_rate_paise: target_rate)
    puts "  FILL #{zone.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: 0 -> #{target_rate}"
    zvtp_filled += 1
  elsif old_per_km > max_rate
    zvtp.update!(per_km_rate_paise: target_rate)
    puts "  CAP  #{zone.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: #{old_per_km} -> #{target_rate}"
    zvtp_fixed += 1
  elsif old_per_km < min_rate
    zvtp.update!(per_km_rate_paise: target_rate)
    puts "  RAISE #{zone.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: #{old_per_km} -> #{target_rate}"
    zvtp_fixed += 1
  end
end
puts "  Fixed #{zvtp_fixed} outliers, filled #{zvtp_filled} zeros"
puts

# =============================================================================
# STEP 4: Verify base fares are reasonable
# =============================================================================
puts "-" * 80
puts "STEP 4: Verify zone base fares"
puts "-" * 80

base_fixed = 0
ZoneVehicleTimePricing.where(active: true).each do |zvtp|
  zvp = ZoneVehiclePricing.find_by(id: zvtp.zone_vehicle_pricing_id)
  next unless zvp

  porter = PORTER_RATES[zvp.vehicle_type]
  next unless porter

  time_mult = TIME_BAND_MULT[zvtp.time_band] || 1.0
  min_base = (porter[:base] * 0.80).round
  max_base = (porter[:base] * MARKUP * time_mult * 2.0).round

  if zvtp.base_fare_paise < min_base
    zone = Zone.find_by(id: zvp.zone_id)
    target_base = (porter[:base] * MARKUP * time_mult).round
    puts "  RAISE #{zone&.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: base #{zvtp.base_fare_paise} -> #{target_base}"
    zvtp.update!(base_fare_paise: target_base, min_fare_paise: target_base)
    base_fixed += 1
  elsif zvtp.base_fare_paise > max_base
    zone = Zone.find_by(id: zvp.zone_id)
    target_base = (porter[:base] * MARKUP * time_mult * 1.2).round
    puts "  CAP  #{zone&.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: base #{zvtp.base_fare_paise} -> #{target_base}"
    zvtp.update!(base_fare_paise: target_base, min_fare_paise: target_base)
    base_fixed += 1
  end
end
puts "  Fixed #{base_fixed} base fare outliers"
puts

# =============================================================================
# SUMMARY
# =============================================================================
puts "=" * 80
puts "RECALIBRATION COMPLETE"
puts "=" * 80
puts "  City defaults: #{updated_configs} updated"
puts "  Zone rates: #{zvp_fixed} capped, #{zvp_filled} filled"
puts "  Zone time rates: #{zvtp_fixed} capped, #{zvtp_filled} filled"
puts "  Base fares: #{base_fixed} adjusted"
puts
puts "Next steps:"
puts "  1. Run: PRICING_MODE=calibration RAILS_ENV=development bundle exec ruby script/test_pricing_engine.rb"
puts "=" * 80
