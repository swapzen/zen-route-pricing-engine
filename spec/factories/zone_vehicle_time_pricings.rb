# frozen_string_literal: true

FactoryBot.define do
  factory :zone_vehicle_time_pricing do
    zone_vehicle_pricing
    time_band { 'morning_rush' }
    base_fare_paise { 6500 }
    min_fare_paise { 6000 }
    per_km_rate_paise { 1700 }
    active { true }
    per_min_rate_paise { 0 }
  end
end
