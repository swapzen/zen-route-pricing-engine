# frozen_string_literal: true

FactoryBot.define do
  factory :pricing_outcome do
    pricing_quote
    city_code { 'tst' }
    outcome { 'accepted' }
    vehicle_type { 'three_wheeler' }
    quoted_price_paise { 15000 }
    pickup_zone_code { 'tst_zone' }
    time_band { 'morning_rush' }
  end
end
