# frozen_string_literal: true

require_relative '../config/environment'

originals = {
  'two_wheeler'   => { base: 4500,   per_km: 0, min_fare: 4500,   base_dist: 1000, per_min: 0 },
  'scooter'       => { base: 6000,   per_km: 0, min_fare: 6000,   base_dist: 1000, per_min: 0 },
  'mini_3w'       => { base: 10000,  per_km: 0, min_fare: 10000,  base_dist: 1000, per_min: 0 },
  'three_wheeler' => { base: 20000,  per_km: 0, min_fare: 20000,  base_dist: 1000, per_min: 0 },
  'tata_ace'      => { base: 25000,  per_km: 0, min_fare: 25000,  base_dist: 1000, per_min: 0 },
  'pickup_8ft'    => { base: 30000,  per_km: 0, min_fare: 30000,  base_dist: 1000, per_min: 0 },
  'canter_14ft'   => { base: 145000, per_km: 0, min_fare: 145000, base_dist: 1000, per_min: 0 }
}

originals.each do |vt, vals|
  config = PricingConfig.find_by(city_code: 'hyd', vehicle_type: vt, active: true)
  config.update!(
    base_fare_paise: vals[:base],
    per_km_rate_paise: vals[:per_km],
    min_fare_paise: vals[:min_fare],
    base_distance_m: vals[:base_dist],
    per_min_rate_paise: vals[:per_min]
  )
  puts "Restored #{vt}: base=#{vals[:base]} per_km=#{vals[:per_km]}"
end
puts "Done - all city defaults restored"
