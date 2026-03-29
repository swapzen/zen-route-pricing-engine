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

  CORRIDOR_CATEGORIES = %w[
    morning_rush_corridors
    business_corridors
    old_city_corridors
    airport_corridors
    industrial_corridors
  ].freeze

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
  # Corridor Sync — extracted from ZoneConfigLoader
  # -------------------------------------------------------------------------
  def sync_corridors!(force: false)
    corridors_path = Rails.root.join('config', 'zones', city_folder, 'corridors')
    return unless corridors_path.exist?

    @corridor_seen_keys ||= {}
    @corridor_seen_keys.clear

    sorted_files = Dir.glob(corridors_path.join('*.yml')).sort_by do |file_path|
      basename = File.basename(file_path)
      priority =
        if basename.start_with?('route_')
          0
        elsif basename == 'priority_corridors.yml'
          1
        else
          2
        end
      [priority, basename]
    end

    sorted_files.each do |file_path|
      sync_corridor_file(file_path, force: force)
    end

    deactivate_stale_corridors!
  end

  private

  def sync_corridor_file(file_path, force: false)
    data = YAML.load_file(file_path)
    source_file = File.basename(file_path)

    if CORRIDOR_CATEGORIES.any? { |category| data.key?(category) }
      sync_multi_corridor_file(data, force: force, source_file: source_file)
    else
      sync_single_corridor(data, force: force, source_file: source_file)
    end
  rescue StandardError => e
    stats[:errors] << { file: File.basename(file_path), error: e.message }
    Rails.logger.error "[ConfigLoader] Error syncing corridor file #{file_path}: #{e.message}"
  end

  def sync_multi_corridor_file(data, force: false, source_file:)
    CORRIDOR_CATEGORIES.each do |category|
      corridors = data[category] || {}
      corridors.each do |corridor_id, corridor_data|
        next unless corridor_data.is_a?(Hash) && corridor_data['from_zone']
        sync_single_corridor(
          corridor_data.merge('corridor_id' => corridor_id),
          force: force,
          source_file: source_file
        )
      end
    end
  end

  def sync_single_corridor(data, force: false, source_file:)
    from_zone_code = data['from_zone']
    to_zone_code = data['to_zone']
    directional = data['directional'] != false
    corridor_id = data['corridor_id'] || 'single'
    source_label = "#{source_file}:#{corridor_id}"

    return unless from_zone_code && to_zone_code

    from_zone = Zone.find_by(city: city_code, zone_code: from_zone_code)
    to_zone = Zone.find_by(city: city_code, zone_code: to_zone_code)

    unless from_zone && to_zone
      Rails.logger.warn "[ConfigLoader] Zones not found for corridor: #{from_zone_code} -> #{to_zone_code}"
      return
    end

    pricing_data = data['pricing'] || {}

    VEHICLE_TYPES.each do |vehicle_type|
      TIME_BANDS.each do |time_band|
        rates = pricing_data.dig(time_band, vehicle_type)
        next unless rates

        sync_corridor_pricing(
          from_zone, to_zone, vehicle_type, time_band, rates, directional,
          source_label: source_label, force: force
        )
      end
    end
  end

  def sync_corridor_pricing(from_zone, to_zone, vehicle_type, time_band, rates, directional, source_label:, force: false)
    @corridor_seen_keys ||= {}
    key = [city_code, from_zone.id, to_zone.id, vehicle_type, time_band]
    existing_source = @corridor_seen_keys[key]

    if existing_source
      return if existing_source == source_label
      stats[:corridor_conflicts] = (stats[:corridor_conflicts] || 0) + 1
      Rails.logger.warn(
        "[ConfigLoader] Duplicate corridor: #{from_zone.zone_code} -> #{to_zone.zone_code} " \
        "(#{vehicle_type}/#{time_band}): keeping #{existing_source}, skipping #{source_label}"
      )
      return
    end

    @corridor_seen_keys[key] = source_label

    corridor = ZonePairVehiclePricing.find_or_initialize_by(
      city_code: city_code,
      from_zone: from_zone,
      to_zone: to_zone,
      vehicle_type: vehicle_type,
      time_band: time_band
    )

    was_new = corridor.new_record?

    if was_new || force
      corridor.assign_attributes(
        base_fare_paise: rates['base'] || 5000,
        per_km_rate_paise: rates['rate'] || 1000,
        per_min_rate_paise: rates['min_rate'] || 0,
        min_fare_paise: rates['base'] || 5000,
        directional: directional,
        active: true
      )

      if corridor.changed?
        corridor.save!
        if was_new
          stats[:corridors_created] = (stats[:corridors_created] || 0) + 1
        else
          stats[:corridors_updated] = (stats[:corridors_updated] || 0) + 1
        end
      end
    end
  end

  def deactivate_stale_corridors!
    @corridor_seen_keys ||= {}
    active_db_corridors = ZonePairVehiclePricing.where(city_code: city_code, active: true, auto_generated: [false, nil])

    active_db_corridors.find_each do |corridor|
      key = [city_code, corridor.from_zone_id, corridor.to_zone_id, corridor.vehicle_type, corridor.time_band]
      next if @corridor_seen_keys.key?(key)

      corridor.update!(active: false)
      stats[:corridors_deactivated] = (stats[:corridors_deactivated] || 0) + 1
    end
  end
end
