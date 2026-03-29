# frozen_string_literal: true

FactoryBot.define do
  factory :vendor_rate_card do
    vendor_code { 'porter' }
    city_code { 'tst' }
    vehicle_type { 'three_wheeler' }
    base_fare_paise { 5000 }
    per_km_rate_paise { 1200 }
    per_min_rate_paise { 150 }
    dead_km_per_km_rate_paise { 800 }
    free_km_m { 2000 }
    min_fare_paise { 4500 }
    effective_from { 1.day.ago }
    active { true }
    time_band { nil }
  end
end
