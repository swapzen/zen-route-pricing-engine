# frozen_string_literal: true

FactoryBot.define do
  factory :zone do
    sequence(:zone_code) { |n| "tst_zone_#{n}" }
    city { 'tst' }
    zone_type { 'tech_corridor' }
    status { true }
    priority { 10 }
    auto_generated { false }
    lat_min { 17.40 }
    lat_max { 17.50 }
    lng_min { 78.30 }
    lng_max { 78.40 }
  end
end
