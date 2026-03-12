# frozen_string_literal: true

class H3SurgeBucket < ApplicationRecord
  validates :h3_index, :city_code, presence: true
  validates :surge_multiplier, numericality: { greater_than_or_equal_to: 0.5, less_than_or_equal_to: 5.0 }
  validates :demand_score, :supply_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  scope :for_city, ->(city_code) { where(city_code: city_code.to_s.downcase) }
  scope :for_hex, ->(h3_index) { where(h3_index: h3_index) }
  scope :for_time_band, ->(band) { band.present? ? where(time_band: [band, nil]) : where(time_band: nil) }
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :surging, -> { where('surge_multiplier > 1.0') }

  # Find the applicable surge for a hex + time band
  # Prefers time-band-specific over general (nil time_band)
  def self.find_surge(h3_index, city_code, time_band = nil)
    candidates = for_city(city_code).for_hex(h3_index).active.order(time_band: :desc).to_a
    # Prefer time-band-specific match
    if time_band.present?
      specific = candidates.find { |c| c.time_band == time_band }
      return specific if specific
    end
    # Fallback to general (nil time_band)
    candidates.find { |c| c.time_band.nil? }
  end
end
