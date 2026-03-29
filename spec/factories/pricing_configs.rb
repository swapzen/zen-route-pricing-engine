# frozen_string_literal: true

FactoryBot.define do
  factory :pricing_config do
    city_code { 'tst' }
    vehicle_type { 'three_wheeler' }
    timezone { 'Asia/Kolkata' }
    base_fare_paise { 5000 }
    min_fare_paise { 4500 }
    per_km_rate_paise { 1500 }
    base_distance_m { 2000 }
    vehicle_multiplier { 1.0 }
    city_multiplier { 1.0 }
    surge_multiplier { 1.0 }
    sequence(:version) { |n| 100 + n }
    active { true }
    approval_status { 'approved' }
    variance_buffer_pct { 0.0 }
    min_margin_pct { 0.0 }
    dead_km_enabled { false }
    free_pickup_radius_m { 2000 }
    dead_km_per_km_rate_paise { 800 }
    per_min_rate_paise { 0 }
    effective_from { 1.day.ago }
    effective_until { nil }
  end
end
