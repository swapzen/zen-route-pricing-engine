# frozen_string_literal: true

class VendorRateCard < ApplicationRecord
  VENDOR_CODES = %w[porter dunzo own_fleet borzo].freeze

  validates :vendor_code, :city_code, :vehicle_type, presence: true
  validates :vendor_code, inclusion: { in: VENDOR_CODES }
  validates :base_fare_paise, :per_km_rate_paise, :min_fare_paise,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :per_min_rate_paise, :dead_km_rate_paise, :free_km_m,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :surge_cap_multiplier, numericality: { greater_than: 0 }
  validates :effective_from, presence: true
  VALID_TIME_BANDS = %w[
    early_morning morning_rush midday afternoon evening_rush night
    weekend_day weekend_night
  ].freeze

  validates :time_band, inclusion: { in: VALID_TIME_BANDS }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :current, -> {
    active
      .where('effective_from <= ?', Time.current)
      .where('effective_until IS NULL OR effective_until > ?', Time.current)
  }
  scope :for_vendor, ->(vendor_code) { where(vendor_code: vendor_code) }
  scope :for_city, ->(city_code) { where(city_code: city_code) }

  # Find the current rate card for a vendor/city/vehicle combo.
  # Tries time-band-specific first, falls back to all-day (time_band: nil).
  def self.current_rate(vendor_code, city_code, vehicle_type, time_band: nil)
    base = current.where(vendor_code: vendor_code, city_code: city_code, vehicle_type: vehicle_type)
                  .order(version: :desc)

    if time_band.present?
      rate = base.find_by(time_band: time_band)
      return rate if rate
    end

    # Fallback to all-day rate
    base.find_by(time_band: nil)
  end
end
