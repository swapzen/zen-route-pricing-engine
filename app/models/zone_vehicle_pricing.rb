class ZoneVehiclePricing < ApplicationRecord
  belongs_to :zone
  has_many :time_pricings, class_name: 'ZoneVehicleTimePricing', dependent: :destroy
  
  validates :city_code, presence: true
  validates :vehicle_type, presence: true
  validates :base_fare_paise, presence: true
  validates :min_fare_paise, presence: true
  validates :base_distance_m, presence: true
  validates :per_km_rate_paise, presence: true

  scope :active, -> { where(active: true) }
  
  # CockroachDB Optimization: composite index usage
  # We look up by [city_code, zone_id, vehicle_type]
end
