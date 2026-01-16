# frozen_string_literal: true

# PricingZoneMultiplier represents geographic zones with demand-based pricing adjustments.
# v4.0: Enhanced with vehicle-category-specific multipliers and multi-zone route support
class PricingZoneMultiplier < ApplicationRecord
  # Vehicle categories (align with PricingConfig)
  SMALL_VEHICLES = %w[two_wheeler scooter mini_3w].freeze
  MID_TRUCKS = %w[three_wheeler three_wheeler_ev tata_ace pickup_8ft].freeze
  HEAVY_TRUCKS = %w[eeco tata_407 canter_14ft].freeze
  
  # Zone types for business logic
  ZONE_TYPES = %w[
    tech_corridor
    business_cbd
    traditional_commercial
    residential_dense
    residential_mixed
    residential_growth
    industrial_logistics
    airport_logistics
  ].freeze
  
  # Validations
  validates :zone_code, presence: true, 
            uniqueness: { scope: :city_code, message: 'already exists for this city' }
  validates :small_vehicle_mult, :mid_truck_mult, :heavy_truck_mult,
            numericality: { greater_than: 0, less_than_or_equal_to: 2.0 }
  validates :zone_type, inclusion: { in: ZONE_TYPES }, allow_nil: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :by_type, ->(zone_type) { where(zone_type: zone_type) }

  # Get multiplier for specific vehicle type
  def multiplier_for_vehicle(vehicle_type)
    case
    when SMALL_VEHICLES.include?(vehicle_type)
      small_vehicle_mult || 1.0
    when MID_TRUCKS.include?(vehicle_type)
      mid_truck_mult || 1.0
    when HEAVY_TRUCKS.include?(vehicle_type)
      heavy_truck_mult || 1.0
    else
      1.0
    end
  end

  # Find zone for given coordinates
  def self.for_coordinates(city_code:, lat:, lng:)
    active.for_city(city_code)
          .where('lat_min <= ? AND lat_max >= ?', lat, lat)
          .where('lng_min <= ? AND lng_max >= ?', lng, lng)
          .first
  end

  # Calculate route multiplier with multi-zone support
  # Returns zone multiplier for a route based on pickup/drop and optional polyline
  def self.route_multiplier(
    city_code:,
    pickup_lat:,
    pickup_lng:,
    drop_lat:,
    drop_lng:,
    vehicle_type:,
    route_polyline: nil
  )
    return 1.0 unless pickup_lat && pickup_lng && drop_lat && drop_lng
    
    # Simple from/to zone logic (polyline support TODO for v4.1)
    from_zone = for_coordinates(city_code: city_code, lat: pickup_lat, lng: pickup_lng)
    to_zone = for_coordinates(city_code: city_code, lat: drop_lat, lng: drop_lng)
    
    # If no zones found, return neutral multiplier
    return 1.0 unless from_zone || to_zone
    
    if from_zone == to_zone && from_zone.present?
      # Intra-zone: use zone's multiplier for this vehicle category
      from_zone.multiplier_for_vehicle(vehicle_type)
    elsif from_zone && to_zone
      # Inter-zone: use max multiplier (route passes through high-demand zone)
      from_mult = from_zone.multiplier_for_vehicle(vehicle_type)
      to_mult = to_zone.multiplier_for_vehicle(vehicle_type)
      [from_mult, to_mult].max
    else
      # Only one zone found: use that zone's multiplier
      zone = from_zone || to_zone
      zone.multiplier_for_vehicle(vehicle_type)
    end
  end
end
