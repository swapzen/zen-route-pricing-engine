# frozen_string_literal: true

FactoryBot.define do
  factory :pricing_distance_slab do
    pricing_config
    min_distance_m { 0 }
    max_distance_m { 5000 }
    per_km_rate_paise { 1500 }
  end
end
