# frozen_string_literal: true

# Zone-specific distance slabs for pricing
# Allows different per-km rates at different distance bands per zone
class ZoneDistanceSlab < ApplicationRecord
  belongs_to :zone
  
  validates :city_code, presence: true
  validates :vehicle_type, presence: true
  validates :min_distance_m, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :per_km_rate_paise, presence: true, numericality: { greater_than: 0 }
  
  scope :active, -> { where(active: true) }
  scope :for_city, ->(city) { where(city_code: city) }
  scope :for_vehicle, ->(vt) { where(vehicle_type: vt) }
  scope :ordered, -> { order(:min_distance_m) }
  
  # Find slabs for a zone and vehicle type
  def self.for_zone_vehicle(zone_id, vehicle_type)
    where(zone_id: zone_id, vehicle_type: vehicle_type, active: true).ordered
  end
  
  # Calculate total cost for a given distance using zone slabs
  def self.calculate_slab_cost(zone_id, vehicle_type, distance_m)
    slabs = for_zone_vehicle(zone_id, vehicle_type)
    return nil if slabs.empty?
    
    total_paise = 0
    remaining_m = distance_m
    
    slabs.each do |slab|
      break if remaining_m <= 0
      
      slab_start_m = slab.min_distance_m
      slab_end_m = slab.max_distance_m || Float::INFINITY
      
      # Calculate meters in this slab
      meters_in_slab = if distance_m <= slab_start_m
                         0
                       elsif distance_m >= slab_end_m
                         slab_end_m - slab_start_m
                       else
                         distance_m - slab_start_m
                       end
      
      meters_to_charge = [meters_in_slab, remaining_m].min
      
      if meters_to_charge > 0
        # Use flat fare if defined, otherwise per-km rate
        if slab.flat_fare_paise && slab_start_m == 0
          total_paise += slab.flat_fare_paise
        else
          km_to_charge = meters_to_charge / 1000.0
          total_paise += (km_to_charge * slab.per_km_rate_paise).round
        end
        remaining_m -= meters_to_charge
      end
    end
    
    total_paise
  end
end
