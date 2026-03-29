# frozen_string_literal: true

FactoryBot.define do
  factory :zone_vehicle_pricing do
    zone
    city_code { 'tst' }
    vehicle_type { 'three_wheeler' }
    base_fare_paise { 6000 }
    min_fare_paise { 5500 }
    per_km_rate_paise { 1600 }
    base_distance_m { 2000 }
    active { true }
    per_min_rate_paise { 0 }
  end
end
