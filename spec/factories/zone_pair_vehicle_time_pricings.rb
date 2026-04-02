# frozen_string_literal: true

FactoryBot.define do
  factory :zone_pair_vehicle_time_pricing do
    association :zone_pair_vehicle_pricing
    time_band { 'morning_rush' }
    base_fare_paise { 7500 }
    min_fare_paise { 7000 }
    per_km_rate_paise { 2000 }
    per_min_rate_paise { 0 }
    active { true }
  end
end
