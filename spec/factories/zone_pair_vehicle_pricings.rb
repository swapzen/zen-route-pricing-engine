# frozen_string_literal: true

FactoryBot.define do
  factory :zone_pair_vehicle_pricing do
    association :from_zone, factory: :zone
    association :to_zone, factory: :zone
    city_code { 'tst' }
    vehicle_type { 'three_wheeler' }
    base_fare_paise { 7000 }
    min_fare_paise { 6500 }
    per_km_rate_paise { 1800 }
    active { true }
    directional { false }
    time_band { nil }
    per_min_rate_paise { 0 }
  end
end
