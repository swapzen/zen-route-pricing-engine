# frozen_string_literal: true

# =============================================================================
# Expand 3-band pricing to 8-band pricing
# =============================================================================
# Reads existing 3-band YAML (morning/afternoon/evening) and generates
# 8 granular time bands with demand-pattern multipliers.
#
# Usage: bundle exec ruby script/expand_to_8_bands.rb
# =============================================================================

require 'yaml'

# Multipliers to derive 8-band rates from parent 3-band rates.
# CRITICAL: morning_rush, afternoon, night MUST be 1.0 to preserve
# benchmark calibration (test uses 9 AM, 3 PM, 11 PM as benchmark times).
BAND_DERIVATION = {
  'early_morning' => { parent: 'morning',   mult: 0.92 }, # 5-8 AM: less demand than rush hour
  'morning_rush'  => { parent: 'morning',   mult: 1.00 }, # 8-11 AM: Benchmark-calibrated at 9 AM
  'midday'        => { parent: 'afternoon', mult: 0.95 }, # 11 AM-2 PM: moderate lull
  'afternoon'     => { parent: 'afternoon', mult: 1.00 }, # 2-5 PM: Benchmark-calibrated at 3 PM
  'evening_rush'  => { parent: 'evening',   mult: 1.12 }, # 5-9 PM: peak return commute premium
  'night'         => { parent: 'evening',   mult: 1.00 }, # 9 PM-5 AM: Benchmark-calibrated at 11 PM
  'weekend_day'   => { parent: 'afternoon', mult: 0.95 }, # Sat/Sun 8 AM-8 PM: less commercial
  'weekend_night' => { parent: 'evening',   mult: 0.90 }, # Sat/Sun 8 PM-8 AM: lower demand
}.freeze

def expand_pricing_hash(pricing_3band)
  return {} if pricing_3band.nil? || pricing_3band.empty?

  pricing_8band = {}

  BAND_DERIVATION.each do |band_name, config|
    parent_band = pricing_3band[config[:parent]]
    next unless parent_band

    mult = config[:mult]
    pricing_8band[band_name] = {}

    parent_band.each do |vehicle_type, rates|
      base = rates['base']
      rate = rates['rate']
      min_rate = rates['min_rate']
      next unless base && rate

      new_entry = {
        'base' => (base * mult).round(-1), # round to nearest 10
        'rate' => (rate * mult).round(-1)
      }
      new_entry['min_rate'] = (min_rate * mult).round(-1) if min_rate && min_rate > 0
      pricing_8band[band_name][vehicle_type] = new_entry
    end
  end

  pricing_8band
end

def expand_inter_zone_adjustments(adjustments_3band)
  return {} if adjustments_3band.nil? || adjustments_3band.empty?

  expanded = {}

  adjustments_3band.each do |pattern, values|
    next unless values.is_a?(Hash)

    morning_val = values['morning'] || 1.0
    afternoon_val = values['afternoon'] || 1.0
    evening_val = values['evening'] || 1.0

    expanded[pattern] = {
      'early_morning' => (morning_val * 0.95).round(2),    # slightly less than morning
      'morning_rush'  => morning_val,                       # preserve calibrated morning
      'midday'        => (afternoon_val * 0.98).round(2),   # close to afternoon
      'afternoon'     => afternoon_val,                     # preserve calibrated afternoon
      'evening_rush'  => (evening_val * 1.05).round(2),     # amplified evening effect
      'night'         => evening_val,                       # preserve calibrated evening
      'weekend_day'   => (afternoon_val * 0.97).round(2),   # slight weekend discount
      'weekend_night' => (evening_val * 0.95).round(2)      # dampened evening weekend
    }
  end

  expanded
end

# ---------------------------------------------------------------------------
# 1. Expand vehicle_defaults.yml
# ---------------------------------------------------------------------------
vd_path = File.expand_path('../../config/zones/hyderabad/vehicle_defaults.yml', __FILE__)
vd = YAML.load_file(vd_path)

old_time_rates = vd['global_time_rates']
vd['global_time_rates'] = expand_pricing_hash(old_time_rates)

# Expand inter-zone adjustments
if vd['inter_zone_formula'] && vd['inter_zone_formula']['type_adjustments']
  vd['inter_zone_formula']['type_adjustments'] = expand_inter_zone_adjustments(
    vd['inter_zone_formula']['type_adjustments']
  )
end

File.write(vd_path, YAML.dump(vd))
puts "vehicle_defaults.yml expanded to 8 bands"

# ---------------------------------------------------------------------------
# 2. Expand h3_zones.yml
# ---------------------------------------------------------------------------
h3_path = File.expand_path('../../config/zones/hyderabad/h3_zones.yml', __FILE__)
h3 = YAML.load_file(h3_path)

zones = h3['zones'] || {}
expanded_count = 0

zones.each do |zone_code, zone_data|
  pricing = zone_data['pricing']
  next unless pricing

  new_pricing = expand_pricing_hash(pricing)
  if new_pricing.any?
    zone_data['pricing'] = new_pricing
    expanded_count += 1
  end
end

h3['zones'] = zones
File.write(h3_path, YAML.dump(h3))
puts "h3_zones.yml: #{expanded_count} zones expanded to 8 bands"

# ---------------------------------------------------------------------------
# 3. Expand corridor YAML files
# ---------------------------------------------------------------------------
corridors_dir = File.expand_path('../../config/zones/hyderabad/corridors', __FILE__)
Dir.glob(File.join(corridors_dir, '*.yml')).each do |corridor_path|
  corridor = YAML.load_file(corridor_path)
  next unless corridor.is_a?(Hash)

  # Single corridor file
  if corridor['pricing']
    corridor['pricing'] = expand_pricing_hash(corridor['pricing'])
    File.write(corridor_path, YAML.dump(corridor))
    puts "Expanded: #{File.basename(corridor_path)}"
    next
  end

  # Multi-corridor file (corridors array)
  if corridor['corridors'].is_a?(Array)
    corridor['corridors'].each do |c|
      next unless c['pricing']
      c['pricing'] = expand_pricing_hash(c['pricing'])
    end
    File.write(corridor_path, YAML.dump(corridor))
    puts "Expanded: #{File.basename(corridor_path)}"
  end
end

puts "\nDone! All YAML files expanded from 3-band to 8-band pricing."
puts "Run 'rails zones:h3_sync[hyd]' to load into database."
