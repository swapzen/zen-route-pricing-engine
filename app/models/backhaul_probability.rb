# frozen_string_literal: true

class BackhaulProbability < ApplicationRecord
  belongs_to :zone

  validates :zone_id, presence: true
  validates :time_band, presence: true
  validates :return_probability, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }
  validates :time_band, uniqueness: { scope: :zone_id }

  scope :for_zone, ->(zone_id) { where(zone_id: zone_id) }
  scope :for_band, ->(band) { where(time_band: band) }
end
