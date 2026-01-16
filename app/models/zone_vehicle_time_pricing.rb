class ZoneVehicleTimePricing < ApplicationRecord
  belongs_to :zone_vehicle_pricing
  
  validates :time_band, presence: true, inclusion: { in: %w[morning afternoon evening] }
  validates :base_fare_paise, presence: true
  validates :min_fare_paise, presence: true
  validates :per_km_rate_paise, presence: true
  
  scope :active, -> { where(active: true) }
  scope :for_time_band, ->(band) { where(time_band: band) }
end
