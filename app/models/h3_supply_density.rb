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

  # Combine supply density with acceptance rate from PricingOutcome
  def pressure_score
    outcomes = PricingOutcome.for_hex(h3_index_r7).recent(24)
    total = outcomes.count
    return 50.0 if total.zero? # neutral when no data

    accepted = outcomes.accepted.count
    acceptance_rate = accepted.to_f / total * 100

    supply_factor = estimated_driver_count > 0 ? [10.0 / estimated_driver_count, 3.0].min : 2.0
    demand_factor = [total / 10.0, 3.0].min
    rejection_factor = [(100.0 - acceptance_rate) / 30.0, 3.0].min

    ((demand_factor + supply_factor + rejection_factor) / 3.0 * 100).round(1)
  end
end
