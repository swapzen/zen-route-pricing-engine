class ZonePairVehiclePricing < ApplicationRecord
  belongs_to :from_zone, class_name: 'Zone'
  belongs_to :to_zone, class_name: 'Zone'
  has_many :time_pricings, class_name: 'ZonePairVehicleTimePricing', dependent: :destroy

  validates :city_code, presence: true
  validates :vehicle_type, presence: true

  scope :active, -> { where(active: true) }
  scope :base_records, -> { where(time_band: nil) }

  # Two-tier lookup: find base record (time_band: nil), then check time_pricings for override
  def self.find_override(city_code, from_zone_id, to_zone_id, vehicle_type, time_band: nil)
    normalized_city = city_code.to_s.downcase

    # 1. Find directional base record (time_band: nil)
    base = where(city_code: normalized_city, from_zone_id: from_zone_id, to_zone_id: to_zone_id,
                 vehicle_type: vehicle_type, time_band: nil, active: true).includes(:time_pricings).first

    # 2. Non-directional swapped base
    base ||= where(city_code: normalized_city, from_zone_id: to_zone_id, to_zone_id: from_zone_id,
                   vehicle_type: vehicle_type, time_band: nil, active: true, directional: false)
                   .includes(:time_pricings).first

    return nil unless base

    # 3. If time_band requested, check for override in time_pricings
    if time_band.present?
      override = base.time_pricings.find { |tp| tp.time_band == time_band && tp.active? }
      return override if override
    end

    # 4. Fall back to base
    base
  end
end
