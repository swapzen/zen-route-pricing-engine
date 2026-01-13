# frozen_string_literal: true

class PricingConfig < ApplicationRecord
  # Associations
  has_many :pricing_surge_rules, dependent: :destroy
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
  
  # Returns current active config for city × vehicle
  scope :current_version, ->(city_code, vehicle_type) {
    where(
      city_code: city_code,
      vehicle_type: vehicle_type,
      active: true,
      effective_until: nil
    ).where('effective_from <= ?', Time.current)
     .order(version: :desc)
     .first
  }

  # Calculate dynamic surge multiplier based on current time and traffic
  def calculate_surge_multiplier(time: Time.current, traffic_ratio: nil)
    # Convert time to city's local timezone
    local_time = time.in_time_zone(timezone)
    
    # Get all active surge rules
    applicable_rules = pricing_surge_rules.active.select do |rule|
      rule.applicable?(time: local_time, traffic_ratio: traffic_ratio)
    end

    # If rules found, multiply their multipliers
    if applicable_rules.any?
      applicable_rules.inject(1.0) { |product, rule| product * rule.multiplier }
    else
      # Fallback to config's surge_multiplier
      surge_multiplier
    end
  end

  # Create new version of this config
  def create_new_version(attrs, user)
    transaction do
      # Mark current version as ended
      self.update!(effective_until: Time.current)

      # Create new version
      new_config = self.dup
      new_config.assign_attributes(attrs.except(:id, :created_at, :updated_at))
      new_config.version = self.version + 1
      new_config.effective_from = Time.current
      new_config.effective_until = nil
      new_config.created_by = user
      new_config.active = true
      new_config.save!

      new_config
    end
  end
end
