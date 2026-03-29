# frozen_string_literal: true

# =============================================================================
# PRICING RECALIBRATION SCRIPT
# =============================================================================
# Fixes pricing miscalibration discovered from 5,250-scenario simulation:
#
# Problems found:
#   1. City default per_km_rate_paise = 0 for ALL vehicles
#   2. Zone outliers: lb_nagar_east per_km up to 42000 paise (₹420/km!)
#   3. Zero per_km for two_wheeler/canter_14ft in several zones
#   4. three_wheeler/tata_ace/pickup_8ft margins 80-104% (way too high)
#   5. two_wheeler/scooter margins -43% to -17% (losing money)
#
# Target: 15-20% margin over Porter's vendor rates across all vehicle types.
#
# USAGE:
#   RAILS_ENV=development bundle exec ruby script/recalibrate_pricing.rb
# =============================================================================

require_relative '../config/environment'

# =============================================================================
# PORTER BENCHMARK RATES (morning, in paise)
# =============================================================================
PORTER_RATES = {
  'two_wheeler'   => { base: 4800,   per_km: 1400, free_km_m: 1000 },
  'scooter'       => { base: 6000,   per_km: 1500, free_km_m: 1000 },
  'mini_3w'       => { base: 10000,  per_km: 1200, free_km_m: 1000 },
  'three_wheeler' => { base: 16100,  per_km: 1800, free_km_m: 2000 },
  'tata_ace'      => { base: 21800,  per_km: 2000, free_km_m: 2000 },
  'pickup_8ft'    => { base: 31800,  per_km: 2500, free_km_m: 2000 },
  'canter_14ft'   => { base: 150000, per_km: 5000, free_km_m: 2000 }
}.freeze

# Target markup over Porter (15-20%)
BASE_MARKUP = 1.15
RATE_MARKUP = 1.20

# Per-km rate bounds (in paise) by vehicle type
# These are the acceptable ranges after markup
PER_KM_BOUNDS = {
  'two_wheeler'   => { min: 1200, max: 2200, target: 1700 },
  'scooter'       => { min: 1300, max: 2400, target: 1800 },
  'mini_3w'       => { min: 1000, max: 1800, target: 1400 },
  'three_wheeler' => { min: 1800, max: 3000, target: 2200 },
  'tata_ace'      => { min: 2000, max: 3200, target: 2400 },
  'pickup_8ft'    => { min: 2500, max: 4000, target: 3000 },
  'canter_14ft'   => { min: 4000, max: 8000, target: 6000 }
}.freeze

# Zone type multipliers for per_km rate adjustment
ZONE_TYPE_RATE_MULT = {
  'tech_corridor'       => 1.00,
  'business_cbd'        => 1.05,
  'residential_dense'   => 1.00,
  'residential_mixed'   => 0.95,
  'residential_growth'  => 0.90,
  'premium_residential' => 1.10,
  'airport_logistics'   => 1.05,
  'industrial'          => 0.95,
  'outer_ring'          => 0.90,
  'traditional_commercial' => 1.05,
  'default'             => 1.00
}.freeze

# Time band multipliers (from Porter afternoon/evening vs morning)
TIME_BAND_MULT = {
  'morning'   => 1.00,
  'afternoon' => 1.10,
  'evening'   => 1.25
}.freeze

puts "=" * 80
puts "PRICING RECALIBRATION"
puts "=" * 80
puts

# =============================================================================
# STEP 1: Fix city default PricingConfig per_km_rate_paise
# =============================================================================
puts "-" * 80
puts "STEP 1: Fix city default PricingConfig per_km_rate_paise"
puts "-" * 80

updated_configs = 0
PricingConfig.where(city_code: 'hyd', active: true).each do |config|
  porter = PORTER_RATES[config.vehicle_type]
  next unless porter

  bounds = PER_KM_BOUNDS[config.vehicle_type]
  new_per_km = bounds[:target]
  new_base = (porter[:base] * BASE_MARKUP).round
  new_min_fare = new_base
  new_base_distance = porter[:free_km_m]

  old_vals = "base=#{config.base_fare_paise} per_km=#{config.per_km_rate_paise} min=#{config.min_fare_paise} base_dist=#{config.base_distance_m}"
  new_vals = "base=#{new_base} per_km=#{new_per_km} min=#{new_min_fare} base_dist=#{new_base_distance}"

  config.update!(
    base_fare_paise: new_base,
    per_km_rate_paise: new_per_km,
    min_fare_paise: new_min_fare,
    base_distance_m: new_base_distance,
    per_min_rate_paise: (porter[:per_km] * 0.15).round  # ~15% of per_km as per-min rate
  )

  puts "  #{config.vehicle_type}: #{old_vals} → #{new_vals}"
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
  max_rate = (bounds[:max] * 1.15).round  # Allow 15% above max for premium zones
  min_rate = (bounds[:min] * 0.85).round  # Allow 15% below min for growth zones

  old_per_km = zvp.per_km_rate_paise

  if old_per_km == 0
    # Fill missing per_km rate
    zvp.update!(per_km_rate_paise: target_rate)
    puts "  FILL #{zone.zone_code}/#{zvp.vehicle_type}: 0 → #{target_rate}"
    zvp_filled += 1
  elsif old_per_km > max_rate
    # Cap excessive rate
    zvp.update!(per_km_rate_paise: target_rate)
    puts "  CAP  #{zone.zone_code}/#{zvp.vehicle_type}: #{old_per_km} → #{target_rate} (was #{(old_per_km.to_f / target_rate).round(1)}x target)"
    zvp_fixed += 1
  elsif old_per_km < min_rate
    # Raise too-low rate
    zvp.update!(per_km_rate_paise: target_rate)
    puts "  RAISE #{zone.zone_code}/#{zvp.vehicle_type}: #{old_per_km} → #{target_rate}"
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
  max_rate = (bounds[:max] * 1.15 * time_mult).round
  min_rate = (bounds[:min] * 0.85).round

  old_per_km = zvtp.per_km_rate_paise

  if old_per_km == 0
    zvtp.update!(per_km_rate_paise: target_rate)
    puts "  FILL #{zone.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: 0 → #{target_rate}"
    zvtp_filled += 1
  elsif old_per_km > max_rate
    zvtp.update!(per_km_rate_paise: target_rate)
    puts "  CAP  #{zone.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: #{old_per_km} → #{target_rate} (was #{(old_per_km.to_f / target_rate).round(1)}x)"
    zvtp_fixed += 1
  elsif old_per_km < min_rate
    zvtp.update!(per_km_rate_paise: target_rate)
    puts "  RAISE #{zone.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: #{old_per_km} → #{target_rate}"
    zvtp_fixed += 1
  end
end
puts "  Fixed #{zvtp_fixed} outliers, filled #{zvtp_filled} zeros"
puts

# =============================================================================
# STEP 4: Fix zone_pair_vehicle_pricing (corridor) per_km rates
# =============================================================================
puts "-" * 80
puts "STEP 4: Fix corridor per_km rate outliers"
puts "-" * 80

corridor_fixed = 0
ZonePairVehiclePricing.where(active: true).each do |zpvp|
  bounds = PER_KM_BOUNDS[zpvp.vehicle_type]
  next unless bounds

  time_mult = TIME_BAND_MULT[zpvp.time_band] || 1.0
  target_rate = (bounds[:target] * time_mult).round
  max_rate = (bounds[:max] * 1.20 * time_mult).round  # Corridors can be slightly higher
  min_rate = (bounds[:min] * 0.80).round  # Corridors can be slightly lower (volume)

  old_per_km = zpvp.per_km_rate_paise

  if old_per_km > max_rate
    from_zone = Zone.find_by(id: zpvp.from_zone_id)
    to_zone = Zone.find_by(id: zpvp.to_zone_id)
    from_code = from_zone&.zone_code || '?'
    to_code = to_zone&.zone_code || '?'
    zpvp.update!(per_km_rate_paise: target_rate)
    puts "  CAP  #{from_code}→#{to_code}/#{zpvp.vehicle_type}/#{zpvp.time_band}: #{old_per_km} → #{target_rate}"
    corridor_fixed += 1
  end
end
puts "  Fixed #{corridor_fixed} corridor outliers"
puts

# =============================================================================
# STEP 5: Verify base fares are reasonable
# =============================================================================
puts "-" * 80
puts "STEP 5: Verify zone base fares"
puts "-" * 80

base_fixed = 0
ZoneVehicleTimePricing.where(active: true).each do |zvtp|
  zvp = ZoneVehiclePricing.find_by(id: zvtp.zone_vehicle_pricing_id)
  next unless zvp

  porter = PORTER_RATES[zvp.vehicle_type]
  next unless porter

  time_mult = TIME_BAND_MULT[zvtp.time_band] || 1.0
  min_base = (porter[:base] * 0.80).round  # Allow 20% below Porter base
  max_base = (porter[:base] * BASE_MARKUP * time_mult * 2.5).round  # Allow up to 2.5x Porter for premium zones

  if zvtp.base_fare_paise < min_base
    zone = Zone.find_by(id: zvp.zone_id)
    target_base = (porter[:base] * BASE_MARKUP * time_mult).round
    puts "  RAISE #{zone&.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: base #{zvtp.base_fare_paise} → #{target_base}"
    zvtp.update!(base_fare_paise: target_base, min_fare_paise: target_base)
    base_fixed += 1
  elsif zvtp.base_fare_paise > max_base
    zone = Zone.find_by(id: zvp.zone_id)
    target_base = (porter[:base] * BASE_MARKUP * time_mult * 1.5).round  # Cap at 1.5x Porter
    puts "  CAP  #{zone&.zone_code}/#{zvp.vehicle_type}/#{zvtp.time_band}: base #{zvtp.base_fare_paise} → #{target_base}"
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
puts "  City defaults: #{updated_configs} updated (per_km set from 0 to target)"
puts "  Zone rates: #{zvp_fixed} capped, #{zvp_filled} filled"
puts "  Zone time rates: #{zvtp_fixed} capped, #{zvtp_filled} filled"
puts "  Corridor rates: #{corridor_fixed} capped"
puts "  Base fares: #{base_fixed} adjusted"
puts
puts "Next steps:"
puts "  1. Run: PRICING_MODE=calibration RAILS_ENV=development bundle exec ruby script/test_pricing_engine.rb"
puts "  2. Run: RAILS_ENV=development bundle exec ruby script/simulate_routes.rb"
puts "  3. Run: RAILS_ENV=development bundle exec ruby script/analyze_simulation.rb"
puts "=" * 80
