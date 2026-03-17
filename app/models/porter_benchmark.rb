# frozen_string_literal: true

class PorterBenchmark < ApplicationRecord
  validates :route_key, presence: true
  validates :pickup_address, presence: true
  validates :drop_address, presence: true
  validates :vehicle_type, presence: true
  validates :time_band, presence: true
  validates :porter_price_inr, numericality: { greater_than: 0, allow_nil: true }

  before_save :compute_delta

  scope :for_city, ->(city) { where(city_code: city) }
  scope :for_band, ->(band) { where(time_band: band) }
  scope :with_both_prices, -> { where.not(porter_price_inr: nil).where.not(our_price_inr: nil) }

  private

  def compute_delta
    return unless porter_price_inr.present? && our_price_inr.present? && porter_price_inr > 0
    self.delta_pct = ((our_price_inr - porter_price_inr).to_f / porter_price_inr * 100).round(1)
  end
end
