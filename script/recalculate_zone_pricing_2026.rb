# frozen_string_literal: true

# =============================================================================
# RECALCULATE ZONE PRICING — 2026 Market Rates
# =============================================================================
# Updates h3_zones.yml with zone-type-adjusted pricing derived from
# 2026 Porter benchmarks + 7% SwapZen markup.
#
# Formula per zone:
#   zone_base  = ROUND(city_default_base × zone_type_mult × time_band_mult)
#   zone_rate  = ROUND(city_default_rate × zone_type_mult × time_band_mult)
#
# USAGE:
#   bundle exec ruby script/recalculate_zone_pricing_2026.rb
# =============================================================================

require 'yaml'

# 2026 city default rates (morning_rush base, in paise)
CITY_DEFAULTS = {
  'two_wheeler'      => { base: 5100,   rate: 1500, per_min: 150 },
  'scooter'          => { base: 6400,   rate: 1600, per_min: 180 },
  'mini_3w'          => { base: 10700,  rate: 1300, per_min: 150 },
  'three_wheeler'    => { base: 17200,  rate: 1900, per_min: 200 },
  'three_wheeler_ev' => { base: 17200,  rate: 1900, per_min: 200 },
  'tata_ace'         => { base: 23300,  rate: 2100, per_min: 250 },
  'pickup_8ft'       => { base: 34000,  rate: 2700, per_min: 300 },
  'eeco'             => { base: 37500,  rate: 3400, per_min: 350 },
  'tata_407'         => { base: 59000,  rate: 4500, per_min: 400 },
  'canter_14ft'      => { base: 160500, rate: 5900, per_min: 600 }
}.freeze

# Zone-type multipliers (premium/discount by area type)
ZONE_TYPE_MULT = {
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

# Time-band multipliers (applied on top of zone_type)
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

TIME_BANDS = TIME_BAND_MULT.keys
VEHICLES = CITY_DEFAULTS.keys

h3_path = File.expand_path('../config/zones/hyderabad/h3_zones.yml', __dir__)
data = YAML.load_file(h3_path)

zones = data['zones'] || {}
updated = 0

zones.each do |zone_code, zone_data|
  zone_type = zone_data['zone_type'] || 'default'
  zt_mult = ZONE_TYPE_MULT[zone_type] || ZONE_TYPE_MULT['default']

  pricing = {}

  TIME_BANDS.each do |band|
    tb_mult = TIME_BAND_MULT[band]
    combined_mult = zt_mult * tb_mult

    band_pricing = {}
    VEHICLES.each do |vehicle|
      defaults = CITY_DEFAULTS[vehicle]
      band_pricing[vehicle] = {
        'base' => (defaults[:base] * combined_mult).round,
        'rate' => (defaults[:rate] * combined_mult).round
      }
    end

    pricing[band] = band_pricing
  end

  zone_data['pricing'] = pricing
  updated += 1
end

data['generated_at'] = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

File.write(h3_path, data.to_yaml)

puts "Updated #{updated} zones in h3_zones.yml"
puts "Zone types found: #{zones.values.map { |z| z['zone_type'] }.tally.sort_by { |_, v| -v }.map { |k, v| "#{k}(#{v})" }.join(', ')}"
puts "\nSample (hitech_city, morning_rush, tata_ace):"
sample = zones.dig('hitech_city', 'pricing', 'morning_rush', 'tata_ace')
if sample
  puts "  base: #{sample['base']} paise (#{sample['base'] / 100.0} INR)"
  puts "  rate: #{sample['rate']} paise (#{sample['rate'] / 100.0} INR)"
else
  # Try first tech_corridor zone
  tc_zone = zones.find { |_, z| z['zone_type'] == 'tech_corridor' }
  if tc_zone
    sample = tc_zone[1].dig('pricing', 'morning_rush', 'tata_ace')
    puts "  (using #{tc_zone[0]})"
    puts "  base: #{sample['base']} paise" if sample
    puts "  rate: #{sample['rate']} paise" if sample
  end
end
