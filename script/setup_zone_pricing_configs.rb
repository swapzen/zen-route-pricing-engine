# frozen_string_literal: true

# Setup Zone-Level Pricing Configurations
# Industry-standard patterns from Cogoport/ShipX:
# - FSC (Fuel Surcharge) by zone
# - Zone Multiplier (SLS) by zone type
# - ODA (Out of Delivery Area) flags
# - Special Location Surcharge for premium areas

puts "=" * 70
puts "SETTING UP ZONE-LEVEL PRICING CONFIGURATIONS"
puts "Industry-standard patterns from Cogoport/ShipX"
puts "=" * 70

# Zone pricing configurations based on zone type and market characteristics
# Hyderabad-specific tuning based on Porter benchmark analysis
ZONE_CONFIGS = {
  # Tech Corridors - Competitive pricing (high volume, many providers)
  'hitech_madhapur' => {
    zone_multiplier: 0.95,      # Slightly lower (high competition)
    fuel_surcharge_pct: 0.0,    # No FSC during calibration
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  'gachibowli' => {
    zone_multiplier: 0.95,
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  'kondapur' => {
    zone_multiplier: 0.98,
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  
  # Business/Financial District - Premium pricing (congestion, parking)
  'fin_district' => {
    zone_multiplier: 1.05,      # 5% premium for CBD
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  'ameerpet_core' => {
    zone_multiplier: 1.02,      # Slight premium (busy area)
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  
  # Residential/Growth Areas - Slight discount (encourage adoption)
  'jntu_kukatpally' => {
    zone_multiplier: 0.98,
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  'lb_nagar_east' => {
    zone_multiplier: 0.98,
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  'vanasthali' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  
  # Old City/Heritage Areas - Neutral (narrow roads offset by lower real estate)
  'old_city' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: false,
    special_location_surcharge_paise: 0
  },
  
  # Industrial/Logistics Zones - ODA for deadhead routes
  'tcs_synergy' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: true,               # ODA flag for industrial
    oda_surcharge_pct: 5.0,     # 5% when both pickup & drop are ODA
    special_location_surcharge_paise: 0
  },
  
  # Outer Ring Areas - ODA
  'secunderabad' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: true,
    oda_surcharge_pct: 5.0,
    special_location_surcharge_paise: 0
  },
  'miyapur' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: true,
    oda_surcharge_pct: 5.0,
    special_location_surcharge_paise: 0
  },
  'kompally' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: true,
    oda_surcharge_pct: 5.0,
    special_location_surcharge_paise: 0
  },
  'outer_ring_south' => {
    zone_multiplier: 1.00,
    fuel_surcharge_pct: 0.0,
    is_oda: true,
    oda_surcharge_pct: 5.0,
    special_location_surcharge_paise: 0
  }
}.freeze

# Default config for zones not in the list
DEFAULT_CONFIG = {
  zone_multiplier: 1.00,
  fuel_surcharge_pct: 0.0,
  is_oda: false,
  oda_surcharge_pct: 5.0,
  special_location_surcharge_paise: 0
}.freeze

ActiveRecord::Base.transaction do
  Zone.active.find_each do |zone|
    config = ZONE_CONFIGS[zone.zone_code] || DEFAULT_CONFIG
    
    # Update zone with pricing configs
    updates = {}
    
    # Only update if column exists (migration may not have run yet)
    updates[:zone_multiplier] = config[:zone_multiplier] if zone.respond_to?(:zone_multiplier=)
    updates[:fuel_surcharge_pct] = config[:fuel_surcharge_pct] if zone.respond_to?(:fuel_surcharge_pct=)
    updates[:is_oda] = config[:is_oda] if zone.respond_to?(:is_oda=)
    updates[:oda_surcharge_pct] = config[:oda_surcharge_pct] || 5.0 if zone.respond_to?(:oda_surcharge_pct=)
    updates[:special_location_surcharge_paise] = config[:special_location_surcharge_paise] if zone.respond_to?(:special_location_surcharge_paise=)
    
    if updates.any?
      zone.update!(updates)
      
      puts "\n#{zone.zone_code} (#{zone.zone_type}):"
      puts "  - Zone Multiplier: #{config[:zone_multiplier]}x"
      puts "  - FSC: #{config[:fuel_surcharge_pct]}%"
      puts "  - ODA: #{config[:is_oda] ? 'YES' : 'NO'}"
      puts "  - Special Location Surcharge: ₹#{config[:special_location_surcharge_paise] / 100.0}"
    else
      puts "⚠️  #{zone.zone_code}: Migration not run yet, skipping config update"
    end
  end
end

puts "\n" + "=" * 70
puts "ZONE PRICING CONFIGS UPDATED!"
puts "=" * 70

# Summary
puts "\nSUMMARY:"
puts "-" * 40

tech_zones = Zone.active.where(zone_type: 'tech_corridor').count
oda_zones = Zone.active.where(is_oda: true).count rescue 0

puts "Total active zones: #{Zone.active.count}"
puts "Tech corridor zones: #{tech_zones}"
puts "ODA zones: #{oda_zones}"
puts "\nNote: FSC set to 0% during Porter calibration. Enable later for production."
