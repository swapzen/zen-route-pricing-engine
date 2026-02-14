# frozen_string_literal: true

class PricingConfig < ApplicationRecord
  # Associations
  has_many :pricing_surge_rules, dependent: :destroy
  has_many :pricing_distance_slabs, dependent: :destroy
  belongs_to :created_by, class_name: 'User', foreign_key: 'created_by_id', optional: true

  # Validations
  validates :city_code, :vehicle_type, :timezone, presence: true
  validates :base_fare_paise, :min_fare_paise, :per_km_rate_paise, 
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :base_distance_m, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :vehicle_multiplier, :city_multiplier, :surge_multiplier,
            numericality: { greater_than: 0 }
  validates :version, numericality: { only_integer: true, greater_than: 0 }

  # Scopes
  scope :active, -> { where(active: true) }
  
  # Returns current active config for city × vehicle (class method, not scope)
  # Note: city_code comparison is case-insensitive
  def self.current_version(city_code, vehicle_type)
    where(city_code: city_code.to_s.downcase)
      .where(
        vehicle_type: vehicle_type,
        active: true,
        effective_until: nil
      )
      .where('effective_from <= ?', Time.current)
      .order(version: :desc)
      .first
  end

  # ================================================================
  # Vehicle groupings: delegated to RoutePricing::VehicleCategories
  # (single source of truth for all vehicle classification)
  # ================================================================

  # ================================================================
  # v3.0: Enhanced surge multiplier with time-of-day + distance awareness
  # ================================================================
  # Calculate dynamic surge multiplier based on time, distance, vehicle type, and traffic
  # @param time [Time] Quote time (defaults to current time)
  # @param distance_km [Float] Trip distance in kilometers
  # @param vehicle_type [String] Vehicle type code
  # @param traffic_ratio [Float] Traffic ratio (ignored for time pricing, kept for compatibility)
  # @return [Float] Surge multiplier (1.0 = no surge)
  def calculate_surge_multiplier(time: Time.current, distance_km: nil, vehicle_type: nil, traffic_ratio: nil)
    # If distance_km or vehicle_type not provided, return 1.0 (neutral)
    return 1.0 unless distance_km && vehicle_type
    
    # Convert time to city's local timezone
    local_time = time.in_time_zone(timezone)
    
    # Determine time band and distance category
    time_period = time_band(local_time.hour)
    dist_category = distance_category(distance_km)

    # Get base multiplier for this vehicle + time period
    base_mult = base_time_multiplier(vehicle_type, time_period)
    
    # Apply distance-aware scaling
    scale = distance_scaler(dist_category)
    
    # Calculate effective multiplier
    effective_mult = 1.0 + (base_mult - 1.0) * scale
    
    # Enhanced logging for debugging (only if detailed logs enabled)
    log_pricing_decision(vehicle_type, time_period, dist_category, base_mult, scale, effective_mult) if ENV['PRICING_DETAILED_LOGS'] == 'true'
    
    effective_mult
  end

  # Create a new config version and sunset the current one.
  # This is called from the admin controller.
  def create_new_version(attrs, user)
    transaction do
      # Mark current version as ended and inactive.
      update!(
        effective_until: Time.current,
        active: false
      )

      new_config = dup
      new_config.assign_attributes(attrs.except(:id, :created_at, :updated_at))
      new_config.version = version + 1
      new_config.effective_from = Time.current
      new_config.effective_until = nil
      new_config.created_by = user
      new_config.active = true
      new_config.save!

      new_config
    end
  end

  private

  # ================================================================
  # v3.0 Helper Methods
  # ================================================================

  def time_band(hour)
    case hour
    when 6...12  then :morning
    when 12...18 then :afternoon
    else              :evening  # 18-6 (includes night)
    end
  end

  def distance_category(distance_km)
    case distance_km
    when 0...5   then :micro
    when 5...12  then :short
    when 12...20 then :medium
    else              :long
    end
  end

  def base_time_multiplier(vehicle_type, time_period)
    category = RoutePricing::VehicleCategories.category_for(vehicle_type)
    case category
    when :small
      small_vehicle_multipliers[time_period] || 1.0
    when :mid
      mid_truck_multipliers[time_period] || 1.0
    when :heavy
      heavy_truck_multipliers[time_period] || 1.0
    end
  end

  def small_vehicle_multipliers
    { morning: 0.98, afternoon: 1.02, evening: 1.00 }  # Near neutral for small
  end

  def mid_truck_multipliers
    { morning: 0.98, afternoon: 1.05, evening: 1.15 }  # Reduced from 1.45
  end

  def heavy_truck_multipliers
    { morning: 1.00, afternoon: 1.05, evening: 1.10 }  # Reduced from 1.25
  end

  def distance_scaler(category)
    { micro: 1.5, short: 1.0, medium: 0.8, long: 0.7 }[category] || 1.0
  end

  def log_pricing_decision(vehicle_type, time_period, dist_category, base_mult, scale, effective_mult)
    Rails.logger.info({
      event: 'v3_time_pricing',
      vehicle_type: vehicle_type,
      time_period: time_period,
      distance_band: dist_category,
      base_multiplier: base_mult.round(3),
      distance_scale: scale.round(3),
      effective_multiplier: effective_mult.round(3)
    }.to_json)
  end


end
