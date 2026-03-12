# frozen_string_literal: true

class H3SupplyDensity < ApplicationRecord
  self.table_name = 'h3_supply_density'

  validates :h3_index_r7, :city_code, :time_band, presence: true
  validates :h3_index_r7, uniqueness: { scope: [:city_code, :time_band] }
  validates :time_band, inclusion: { in: %w[morning afternoon evening] }
  validates :avg_pickup_distance_m, numericality: { only_integer: true, greater_than: 0 }
  validates :estimated_driver_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_cell, ->(h3_index, city_code, time_band) {
    where(h3_index_r7: h3_index, city_code: city_code, time_band: time_band)
  }

  scope :for_city, ->(city_code) { where(city_code: city_code) }
end
