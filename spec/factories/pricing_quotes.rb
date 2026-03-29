# frozen_string_literal: true

FactoryBot.define do
  factory :pricing_quote do
    city_code { 'tst' }
    vehicle_type { 'three_wheeler' }
    price_paise { 15000 }
    distance_m { 8000 }
    duration_s { 1200 }
    pickup_raw_lat { 17.44 }
    pickup_raw_lng { 78.37 }
    drop_raw_lat { 17.44 }
    drop_raw_lng { 78.32 }
    pickup_norm_lat { 17.44 }
    pickup_norm_lng { 78.37 }
    drop_norm_lat { 17.44 }
    drop_norm_lng { 78.32 }
    pricing_version { 1 }
    valid_until { 15.minutes.from_now }
    breakdown_json { { pricing_source: :city_default, base_fare: 5000, final_price: 15000 }.to_json }
  end
end
