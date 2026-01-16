# frozen_string_literal: true
#
# Setup pricing for newly created zones
# Following Uber/Rapido patterns - zone type determines pricing tier

puts "=" * 80
puts "== SETTING UP PRICING FOR NEW ZONES =="
puts "=" * 80

VEHICLE_TYPES = %w[two_wheeler scooter mini_3w three_wheeler tata_ace pickup_8ft canter_14ft].freeze

TIME_BANDS = %w[morning afternoon evening].freeze

# Pricing templates by zone type (in paise)
# Pattern: Tech corridors = competitive, CBD = premium, Residential = moderate
ZONE_TYPE_PRICING = {
  'tech_corridor' => {
    'two_wheeler' => { morning: [4000, 500], afternoon: [4500, 550], evening: [4000, 500] },
    'scooter' => { morning: [5500, 600], afternoon: [6500, 650], evening: [5500, 600] },
    'mini_3w' => { morning: [9000, 750], afternoon: [11000, 850], evening: [9000, 750] },
    'three_wheeler' => { morning: [18000, 1600], afternoon: [20000, 1800], evening: [30000, 2200] },
    'tata_ace' => { morning: [22000, 1700], afternoon: [24000, 1900], evening: [36000, 2400] },
    'pickup_8ft' => { morning: [30000, 1800], afternoon: [34000, 2000], evening: [48000, 2600] },
    'canter_14ft' => { morning: [120000, 2800], afternoon: [130000, 3000], evening: [150000, 3400] }
  },
  'business_cbd' => {
    'two_wheeler' => { morning: [4500, 600], afternoon: [5500, 650], evening: [4500, 600] },
    'scooter' => { morning: [6500, 750], afternoon: [7500, 800], evening: [6500, 750] },
    'mini_3w' => { morning: [11000, 900], afternoon: [14000, 1000], evening: [11000, 900] },
    'three_wheeler' => { morning: [28000, 2000], afternoon: [32000, 2200], evening: [44000, 2600] },
    'tata_ace' => { morning: [34000, 2100], afternoon: [38000, 2300], evening: [52000, 2800] },
    'pickup_8ft' => { morning: [42000, 2200], afternoon: [48000, 2400], evening: [64000, 3000] },
    'canter_14ft' => { morning: [145000, 3600], afternoon: [155000, 3800], evening: [180000, 4200] }
  },
  'residential_dense' => {
    'two_wheeler' => { morning: [4000, 550], afternoon: [5000, 600], evening: [4000, 550] },
    'scooter' => { morning: [6000, 650], afternoon: [7000, 700], evening: [6000, 650] },
    'mini_3w' => { morning: [10000, 800], afternoon: [12000, 900], evening: [10000, 800] },
    'three_wheeler' => { morning: [24000, 1800], afternoon: [28000, 2000], evening: [42000, 2400] },
    'tata_ace' => { morning: [30000, 1900], afternoon: [34000, 2100], evening: [50000, 2600] },
    'pickup_8ft' => { morning: [38000, 2000], afternoon: [44000, 2200], evening: [62000, 2800] },
    'canter_14ft' => { morning: [140000, 3400], afternoon: [150000, 3600], evening: [175000, 4000] }
  },
  'residential_mixed' => {
    'two_wheeler' => { morning: [4200, 700], afternoon: [5000, 750], evening: [4200, 700] },
    'scooter' => { morning: [6000, 850], afternoon: [7000, 900], evening: [6000, 850] },
    'mini_3w' => { morning: [10000, 1000], afternoon: [13000, 1100], evening: [10000, 1000] },
    'three_wheeler' => { morning: [26000, 2000], afternoon: [30000, 2100], evening: [44000, 2500] },
    'tata_ace' => { morning: [32000, 2100], afternoon: [36000, 2200], evening: [52000, 2700] },
    'pickup_8ft' => { morning: [40000, 2200], afternoon: [46000, 2400], evening: [64000, 3000] },
    'canter_14ft' => { morning: [150000, 4000], afternoon: [160000, 4200], evening: [190000, 4800] }
  },
  'residential_growth' => {
    'two_wheeler' => { morning: [3800, 650], afternoon: [4500, 700], evening: [3800, 650] },
    'scooter' => { morning: [5500, 800], afternoon: [6500, 850], evening: [5500, 800] },
    'mini_3w' => { morning: [9000, 950], afternoon: [12000, 1050], evening: [9000, 950] },
    'three_wheeler' => { morning: [24000, 1900], afternoon: [28000, 2000], evening: [40000, 2400] },
    'tata_ace' => { morning: [30000, 2000], afternoon: [34000, 2100], evening: [48000, 2500] },
    'pickup_8ft' => { morning: [38000, 2100], afternoon: [44000, 2300], evening: [60000, 2800] },
    'canter_14ft' => { morning: [145000, 3800], afternoon: [155000, 4000], evening: [185000, 4600] }
  },
  'traditional_commercial' => {
    'two_wheeler' => { morning: [4500, 700], afternoon: [6000, 800], evening: [4500, 700] },
    'scooter' => { morning: [6500, 850], afternoon: [8000, 950], evening: [6500, 850] },
    'mini_3w' => { morning: [11000, 1000], afternoon: [14000, 1100], evening: [11000, 1000] },
    'three_wheeler' => { morning: [28000, 2100], afternoon: [34000, 2300], evening: [46000, 2700] },
    'tata_ace' => { morning: [34000, 2200], afternoon: [40000, 2400], evening: [54000, 2900] },
    'pickup_8ft' => { morning: [44000, 2300], afternoon: [52000, 2500], evening: [68000, 3100] },
    'canter_14ft' => { morning: [155000, 4000], afternoon: [165000, 4200], evening: [195000, 4800] }
  },
  'airport_logistics' => {
    'two_wheeler' => { morning: [5000, 800], afternoon: [6000, 850], evening: [5000, 800] },
    'scooter' => { morning: [7000, 950], afternoon: [8500, 1000], evening: [7000, 950] },
    'mini_3w' => { morning: [12000, 1100], afternoon: [15000, 1200], evening: [12000, 1100] },
    'three_wheeler' => { morning: [30000, 2200], afternoon: [36000, 2400], evening: [48000, 2800] },
    'tata_ace' => { morning: [38000, 2300], afternoon: [44000, 2500], evening: [58000, 3000] },
    'pickup_8ft' => { morning: [48000, 2500], afternoon: [56000, 2700], evening: [72000, 3200] },
    'canter_14ft' => { morning: [170000, 4400], afternoon: [185000, 4600], evening: [220000, 5200] }
  }
}

# Setup pricing for each active zone
Zone.for_city('hyd').active.each do |zone|
  pricing_template = ZONE_TYPE_PRICING[zone.zone_type]
  
  unless pricing_template
    puts "⚠️  No pricing template for zone type: #{zone.zone_type} (#{zone.zone_code})"
    next
  end
  
  puts "\n📍 #{zone.zone_code} (#{zone.zone_type})"
  
  VEHICLE_TYPES.each do |vehicle|
    vehicle_pricing = pricing_template[vehicle]
    next unless vehicle_pricing
    
    # Find or create zone vehicle pricing
    zvp = ZoneVehiclePricing.find_or_initialize_by(
      city_code: 'hyd',
      zone: zone,
      vehicle_type: vehicle
    )
    
    # Use morning as base rate
    zvp.update!(
      base_fare_paise: vehicle_pricing[:morning][0],
      min_fare_paise: vehicle_pricing[:morning][0],
      per_km_rate_paise: vehicle_pricing[:morning][1],
      base_distance_m: 1000,
      active: true
    )
    
    # Create/update time-band pricing
    TIME_BANDS.each do |band|
      rates = vehicle_pricing[band.to_sym]
      
      time_pricing = ZoneVehicleTimePricing.find_or_initialize_by(
        zone_vehicle_pricing: zvp,
        time_band: band
      )
      
      time_pricing.update!(
        base_fare_paise: rates[0],
        min_fare_paise: rates[0],
        per_km_rate_paise: rates[1],
        active: true
      )
    end
  end
  
  puts "   ✅ Setup #{VEHICLE_TYPES.count} vehicles × #{TIME_BANDS.count} time bands"
end

puts "\n" + "=" * 80
puts "✅ Zone pricing setup complete!"
puts "=" * 80

# Summary
puts "\n📊 PRICING SUMMARY BY ZONE TYPE (2W Morning):\n"
Zone.for_city('hyd').active.order(:zone_type, :zone_code).each do |z|
  zvp = ZoneVehiclePricing.find_by(zone: z, vehicle_type: 'two_wheeler', active: true)
  if zvp
    tp = zvp.time_pricings.find_by(time_band: 'morning', active: true)
    if tp
      puts "#{z.zone_code.ljust(20)} (#{z.zone_type.ljust(22)}): ₹#{tp.base_fare_paise/100.0} + ₹#{tp.per_km_rate_paise/100.0}/km"
    end
  end
end
