# frozen_string_literal: true

# Shared constants and methods between H3ZoneConfigLoader and ZoneConfigLoader.
# Extracts: vehicle types, time bands, city folder mapping, priority defaults,
# vehicle defaults loading, and corridor sync logic.
module ConfigLoaderShared
  extend ActiveSupport::Concern

  VEHICLE_TYPES = RoutePricing::VehicleCategories::ALL_VEHICLES
  TIME_BANDS = %w[
    early_morning morning_rush midday afternoon evening_rush night
    weekend_day weekend_night
  ].freeze

  CITY_FOLDER_MAP = {
    'hyd' => 'hyderabad',
    'blr' => 'bangalore',
    'mum' => 'mumbai',
    'del' => 'delhi',
    'che' => 'chennai',
    'pun' => 'pune'
  }.freeze

  ZONE_TYPE_PRIORITIES = {
    'tech_corridor' => 20,
    'business_cbd' => 18,
    'heritage_commercial' => 18,
    'premium_residential' => 16,
    'airport_logistics' => 15,
    'traditional_commercial' => 14,
    'industrial' => 12,
    'residential_dense' => 10,
    'residential_mixed' => 10,
    'residential_growth' => 8,
    'outer_ring' => 5,
    'default' => 10
  }.freeze

  def city_folder
    CITY_FOLDER_MAP.fetch(city_code, city_code)
  end

  def default_priority_for_type(zone_type)
    ZONE_TYPE_PRIORITIES.fetch(zone_type.to_s, 5)
  end

  def load_vehicle_defaults
    path = Rails.root.join('config', 'zones', city_folder, 'vehicle_defaults.yml')
    return {} unless path.exist?

    YAML.load_file(path) || {}
  end

  # -------------------------------------------------------------------------
  # Corridor Sync — disabled (corridors deactivated in favor of inter-zone formula)
  # -------------------------------------------------------------------------
  def sync_corridors!(force: false)
    Rails.logger.info "[ConfigLoader] Corridor sync skipped — corridors deactivated"
  end
end
