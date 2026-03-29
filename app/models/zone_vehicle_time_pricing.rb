class ZoneVehicleTimePricing < ApplicationRecord
  belongs_to :zone_vehicle_pricing

  VALID_TIME_BANDS = %w[
    early_morning morning_rush midday afternoon evening_rush night
    weekend_day weekend_night
  ].freeze

  validates :time_band, presence: true, inclusion: { in: VALID_TIME_BANDS }
  validates :base_fare_paise, presence: true
  validates :min_fare_paise, presence: true
  validates :per_km_rate_paise, presence: true
  
  scope :active, -> { where(active: true) }
  scope :for_time_band, ->(band) { where(time_band: band) }
end
