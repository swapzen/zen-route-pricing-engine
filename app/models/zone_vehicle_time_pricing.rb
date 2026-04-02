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

  def active?
    active == true
  end

  def time_band_label
    case time_band
    when 'early_morning' then 'Early Morning (5-8)'
    when 'morning_rush' then 'Morning Rush (8-11)'
    when 'midday' then 'Midday (11-14)'
    when 'afternoon' then 'Afternoon (14-17)'
    when 'evening_rush' then 'Evening Rush (17-21)'
    when 'night' then 'Night (21-5)'
    when 'weekend_day' then 'Weekend Day (8-20)'
    when 'weekend_night' then 'Weekend Night (20-8)'
    else time_band&.titleize || '—'
    end
  end
end
