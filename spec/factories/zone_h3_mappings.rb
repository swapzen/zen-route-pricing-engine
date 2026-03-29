# frozen_string_literal: true

FactoryBot.define do
  factory :zone_h3_mapping do
    zone
    city_code { 'tst' }
    sequence(:h3_index_r7) { |n| "87196#{n.to_s(16).rjust(4, '0')}ffffff" }
    is_boundary { false }
    serviceable { true }
  end
end
