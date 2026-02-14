class ZonePairVehiclePricing < ApplicationRecord
  belongs_to :from_zone, class_name: 'Zone'
  belongs_to :to_zone, class_name: 'Zone'

  validates :city_code, presence: true
  validates :vehicle_type, presence: true
  
  scope :active, -> { where(active: true) }

  def self.find_override(city_code, from_zone_id, to_zone_id, vehicle_type, time_band: nil)
    # Check exact directive match with time_band support
    # Index: idx_zpvp_routing_with_time_band [city_code, from_zone_id, to_zone_id, vehicle_type, time_band]
    # Note: city_code is case-insensitive
    # time_band can be nil (for backward compatibility) or one of: 'morning', 'afternoon', 'evening'
    
    # Try exact match with time_band first
    override = where(city_code: city_code.to_s.downcase)
      .where(
        from_zone_id: from_zone_id,
        to_zone_id: to_zone_id,
        vehicle_type: vehicle_type,
        time_band: time_band,
        active: true
      ).first

    return override if override

    # If no time-band specific match, try without time_band (backward compatibility)
    if time_band.present?
      override = where(city_code: city_code.to_s.downcase)
        .where(
          from_zone_id: from_zone_id,
          to_zone_id: to_zone_id,
          vehicle_type: vehicle_type,
          time_band: nil,
          active: true
        ).first
      
      return override if override
    end

    # Check non-directional match (A -> B might be stored as B -> A with directional=false)
    # Try with time_band first
    override = where(city_code: city_code.to_s.downcase)
      .where(
        from_zone_id: to_zone_id, # Swapped
        to_zone_id: from_zone_id, # Swapped
        vehicle_type: vehicle_type,
        time_band: time_band,
        active: true,
        directional: false
      ).first

    return override if override

    # If no time-band specific match, try without time_band
    if time_band.present?
      where(city_code: city_code.to_s.downcase)
        .where(
          from_zone_id: to_zone_id, # Swapped
          to_zone_id: from_zone_id, # Swapped
          vehicle_type: vehicle_type,
          time_band: nil,
          active: true,
          directional: false
        ).first
    else
      nil
    end
  end
end
