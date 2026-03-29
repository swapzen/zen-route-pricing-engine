# frozen_string_literal: true
require 'set'

# =============================================================================
# Zone Config Loader Service
# =============================================================================
# Loads zone configurations from YAML files and syncs to database.
#
# ARCHITECTURE:
# - YAML is the baseline/initial config source
# - Database is the runtime store for all associations
# - Sync creates new zones but preserves existing pricing edits
# - Admin can edit pricing directly in DB without losing changes
#
# USAGE:
#   ZoneConfigLoader.new('hyd').sync!
#   ZoneConfigLoader.new('hyd').sync!(force_pricing: true)  # Overwrite pricing
# =============================================================================

class ZoneConfigLoader
  include ConfigLoaderShared

  attr_reader :city_code, :config, :stats

  # Keep CITY_FILE_MAPPING for backward compat (zones:status task references it)
  CITY_FILE_MAPPING = CITY_FOLDER_MAP.merge('chn' => 'chennai').freeze

  def initialize(city_code)
    @city_code = city_code.downcase
    @config = load_config
    @stats = { 
      zones_created: 0, 
      zones_updated: 0, 
      zones_skipped: 0,
      zone_pricings_created: 0,
      zone_pricings_updated: 0,
      time_pricings_created: 0,
      corridors_created: 0,
      corridors_updated: 0,
      corridors_deactivated: 0,
      corridor_conflicts: 0,
      validation_errors: [],
      validation_warnings: [],
      errors: [] 
    }
    @corridor_seen_keys = {}
  end

  # ---------------------------------------------------------------------------
  # Main sync method
  # ---------------------------------------------------------------------------
  def sync!(force_pricing: false)
    Rails.logger.warn(
      "[DEPRECATION] ZoneConfigLoader is deprecated. Use H3ZoneConfigLoader instead: " \
      "H3ZoneConfigLoader.new('#{city_code}').sync!(force_pricing: #{force_pricing})"
    )

    return { success: false, error: "No config found for city: #{city_code}" } unless config

    Rails.logger.info "[ZoneConfigLoader] Starting sync for #{city_code}..."

    validation = validate_configuration
    stats[:validation_errors] = validation[:errors]
    stats[:validation_warnings] = validation[:warnings]
    validation[:warnings].each { |w| Rails.logger.warn("[ZoneConfigLoader] #{w}") }

    if validation[:errors].any?
      log_results
      return {
        success: false,
        error: "Configuration validation failed",
        validation: validation
      }
    end
    
    ActiveRecord::Base.transaction do
      sync_zones!
      sync_zone_multipliers! # Legacy table for backward compatibility
      sync_zone_pricing!(force: force_pricing)
      sync_corridors!(force: force_pricing)
    end

    log_results
    { success: true, stats: stats }
  rescue StandardError => e
    Rails.logger.error "[ZoneConfigLoader] Sync failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    { success: false, error: e.message, backtrace: e.backtrace.first(5) }
  end

  # ---------------------------------------------------------------------------
  # Dry run - shows what would be synced without making changes
  # ---------------------------------------------------------------------------
  def dry_run
    return { success: false, error: "No config found for city: #{city_code}" } unless config

    zones = config['zones'] || {}
    existing = Zone.for_city(city_code).pluck(:zone_code)
    validation = validate_configuration
    
    pricing_files = Dir.glob(pricing_dir.join('*.yml'))
    corridor_files = Dir.glob(corridors_dir.join('*.yml'))
    
    {
      city_code: city_code,
      total_zones_in_yaml: zones.count,
      existing_zones_in_db: existing.count,
      new_zones: (zones.keys - existing),
      zones_to_update: (zones.keys & existing),
      in_db_not_in_yaml: (existing - zones.keys),
      pricing_files: pricing_files.map { |f| File.basename(f) },
      corridor_files: corridor_files.map { |f| File.basename(f) },
      validation: validation
    }
  end

  private

  # ---------------------------------------------------------------------------
  # Load YAML config file
  # ---------------------------------------------------------------------------
  def config_dir
    Rails.root.join('config', 'zones')
  end

  def city_config_dir
    config_dir.join(city_folder)
  end

  def pricing_dir
    city_config_dir.join('pricing')
  end

  def corridors_dir
    city_config_dir.join('corridors')
  end

  def load_config
    config_path = config_dir.join("#{city_folder}.yml")
    
    return nil unless File.exist?(config_path)

    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "[ZoneConfigLoader] Failed to load config: #{e.message}"
    nil
  end

  # ---------------------------------------------------------------------------
  # Configuration validation
  # ---------------------------------------------------------------------------
  def validate_configuration
    errors = []
    warnings = []
    zone_codes = Set.new((config['zones'] || {}).keys)

    validate_pricing_files(zone_codes, errors)
    validate_corridor_files(zone_codes, errors, warnings)

    {
      errors: errors.uniq,
      warnings: warnings.uniq
    }
  end

  def validate_pricing_files(zone_codes, errors)
    return unless pricing_dir.exist?

    Dir.glob(pricing_dir.join('*.yml')).each do |file_path|
      data = YAML.load_file(file_path)
      zone_code = data['zone_code']
      if zone_code.blank?
        errors << "Pricing file #{File.basename(file_path)} missing zone_code"
        next
      end

      next if zone_codes.include?(zone_code)

      errors << "Pricing file #{File.basename(file_path)} references unknown zone '#{zone_code}'"
    rescue StandardError => e
      errors << "Failed to parse pricing file #{File.basename(file_path)}: #{e.message}"
    end
  end

  def validate_corridor_files(zone_codes, errors, warnings)
    return unless corridors_dir.exist?

    pair_sources = Hash.new { |h, k| h[k] = [] }

    Dir.glob(corridors_dir.join('*.yml')).each do |file_path|
      data = YAML.load_file(file_path)
      corridor_entries = extract_corridor_entries(data, File.basename(file_path))

      corridor_entries.each do |entry|
        from_zone = entry[:from_zone]
        to_zone = entry[:to_zone]

        if from_zone.blank? || to_zone.blank?
          errors << "Corridor #{entry[:source]} missing from_zone/to_zone"
          next
        end

        errors << "Corridor #{entry[:source]} references unknown from_zone '#{from_zone}'" unless zone_codes.include?(from_zone)
        errors << "Corridor #{entry[:source]} references unknown to_zone '#{to_zone}'" unless zone_codes.include?(to_zone)

        pair_key = [from_zone, to_zone]
        pair_sources[pair_key] << entry[:source]
      end
    rescue StandardError => e
      errors << "Failed to parse corridor file #{File.basename(file_path)}: #{e.message}"
    end

    pair_sources.each do |(from_zone, to_zone), sources|
      next unless sources.size > 1

      warnings << "Duplicate corridor pair #{from_zone} -> #{to_zone}: #{sources.join(', ')}"
    end
  end

  def extract_corridor_entries(data, source_file)
    return [] unless data.is_a?(Hash)

    if CORRIDOR_CATEGORIES.any? { |category| data.key?(category) }
      CORRIDOR_CATEGORIES.flat_map do |category|
        (data[category] || {}).filter_map do |corridor_id, corridor_data|
          next unless corridor_data.is_a?(Hash)
          {
            source: "#{source_file}:#{corridor_id}",
            from_zone: corridor_data['from_zone'],
            to_zone: corridor_data['to_zone']
          }
        end
      end
    else
      [{
        source: source_file,
        from_zone: data['from_zone'],
        to_zone: data['to_zone']
      }]
    end
  end

  # ---------------------------------------------------------------------------
  # Sync zones to database
  # ---------------------------------------------------------------------------
  def sync_zones!
    zones = config['zones'] || {}
    
    zones.each do |zone_code, zone_data|
      sync_zone(zone_code, zone_data)
    end
  end

  def sync_zone(zone_code, data)
    zone = Zone.find_or_initialize_by(city: city_code, zone_code: zone_code)
    
    was_new = zone.new_record?
    
    zone.assign_attributes(
      name: data['name'],
      zone_type: data['zone_type'],
      status: data['active'] || false,
      lat_min: data.dig('bounds', 'lat_min'),
      lat_max: data.dig('bounds', 'lat_max'),
      lng_min: data.dig('bounds', 'lng_min'),
      lng_max: data.dig('bounds', 'lng_max'),
      priority: data['priority'] || default_priority_for_zone_type(data['zone_type'])
    )

    if zone.changed?
      zone.save!
      if was_new
        stats[:zones_created] += 1
        Rails.logger.info "[ZoneConfigLoader] Created zone: #{zone_code}"
      else
        stats[:zones_updated] += 1
        Rails.logger.info "[ZoneConfigLoader] Updated zone: #{zone_code}"
      end
    else
      stats[:zones_skipped] += 1
    end
  rescue StandardError => e
    stats[:errors] << { zone_code: zone_code, error: e.message }
    Rails.logger.error "[ZoneConfigLoader] Error syncing zone #{zone_code}: #{e.message}"
  end

  alias default_priority_for_zone_type default_priority_for_type

  # ---------------------------------------------------------------------------
  # Sync to PricingZoneMultipliers (legacy backward compatibility)
  # ---------------------------------------------------------------------------
  def sync_zone_multipliers!
    zones = config['zones'] || {}
    
    zones.each do |zone_code, data|
      multiplier = PricingZoneMultiplier.find_or_initialize_by(
        city_code: city_code,
        zone_code: zone_code
      )
      
      multiplier.assign_attributes(
        zone_name: data['name'],
        zone_type: data['zone_type'],
        lat_min: data.dig('bounds', 'lat_min'),
        lat_max: data.dig('bounds', 'lat_max'),
        lng_min: data.dig('bounds', 'lng_min'),
        lng_max: data.dig('bounds', 'lng_max'),
        small_vehicle_mult: data.dig('multipliers', 'small_vehicle') || 1.0,
        mid_truck_mult: data.dig('multipliers', 'mid_truck') || 1.0,
        heavy_truck_mult: data.dig('multipliers', 'heavy_truck') || 1.0,
        multiplier: data.dig('multipliers', 'default') || 1.0,
        active: data['active'] || false
      )
      
      multiplier.save! if multiplier.changed?
    end
  end

  # ---------------------------------------------------------------------------
  # Sync Zone-Specific Pricing from pricing/*.yml files
  # ---------------------------------------------------------------------------
  def sync_zone_pricing!(force: false)
    return unless pricing_dir.exist?

    vehicle_defaults = load_vehicle_defaults
    global_time_rates = vehicle_defaults&.dig('global_time_rates') || {}

    Dir.glob(pricing_dir.join('*.yml')).each do |file_path|
      sync_zone_pricing_file(file_path, global_time_rates, force: force)
    end
  end

  def sync_zone_pricing_file(file_path, global_time_rates, force: false)
    data = YAML.load_file(file_path)
    zone_code = data['zone_code']
    
    return unless zone_code

    zone = Zone.find_by(city: city_code, zone_code: zone_code)
    unless zone
      Rails.logger.warn "[ZoneConfigLoader] Zone not found for pricing: #{zone_code}"
      return
    end

    pricing_data = data['pricing'] || {}
    
    VEHICLE_TYPES.each do |vehicle_type|
      sync_vehicle_zone_pricing(zone, vehicle_type, pricing_data, global_time_rates, force: force)
    end
  rescue StandardError => e
    stats[:errors] << { file: File.basename(file_path), error: e.message }
    Rails.logger.error "[ZoneConfigLoader] Error syncing pricing file #{file_path}: #{e.message}"
  end

  def sync_vehicle_zone_pricing(zone, vehicle_type, pricing_data, global_time_rates, force: false)
    # Get default rates from morning time band (or first available)
    default_rates = pricing_data.dig('morning', vehicle_type) || 
                    pricing_data.dig('afternoon', vehicle_type) ||
                    global_time_rates.dig('morning', vehicle_type) ||
                    { 'base' => 5000, 'rate' => 1000 }

    # Find or create zone vehicle pricing
    zone_pricing = ZoneVehiclePricing.find_or_initialize_by(
      city_code: city_code,
      zone: zone,
      vehicle_type: vehicle_type
    )

    was_new = zone_pricing.new_record?

    # Only update if new or force mode
    if was_new || force
      zone_pricing.assign_attributes(
        base_fare_paise: default_rates['base'] || 5000,
        per_km_rate_paise: default_rates['rate'] || 1000,
        per_min_rate_paise: default_rates['min_rate'] || 0,
        min_fare_paise: default_rates['base'] || 5000,
        base_distance_m: 1000,
        active: true
      )

      if zone_pricing.changed?
        zone_pricing.save!
        if was_new
          stats[:zone_pricings_created] += 1
        else
          stats[:zone_pricings_updated] += 1
        end
      end
    end

    # Sync time-band pricing
    TIME_BANDS.each do |time_band|
      rates = pricing_data.dig(time_band, vehicle_type) || 
              global_time_rates.dig(time_band, vehicle_type)
      
      next unless rates

      sync_time_pricing(zone_pricing, time_band, rates, force: force)
    end
  end

  def sync_time_pricing(zone_pricing, time_band, rates, force: false)
    time_pricing = ZoneVehicleTimePricing.find_or_initialize_by(
      zone_vehicle_pricing: zone_pricing,
      time_band: time_band
    )

    was_new = time_pricing.new_record?

    if was_new || force
      time_pricing.assign_attributes(
        base_fare_paise: rates['base'] || 5000,
        per_km_rate_paise: rates['rate'] || 1000,
        per_min_rate_paise: rates['min_rate'] || 0,
        min_fare_paise: rates['base'] || 5000,
        active: true
      )

      if time_pricing.changed?
        time_pricing.save!
        stats[:time_pricings_created] += 1 if was_new
      end
    end
  end

  # Corridor sync is now provided by ConfigLoaderShared concern.

  # ---------------------------------------------------------------------------
  # Logging
  # ---------------------------------------------------------------------------
  def log_results
    Rails.logger.info "[ZoneConfigLoader] Sync complete for #{city_code}:"
    Rails.logger.info "  - Zones created: #{stats[:zones_created]}"
    Rails.logger.info "  - Zones updated: #{stats[:zones_updated]}"
    Rails.logger.info "  - Zones skipped: #{stats[:zones_skipped]}"
    Rails.logger.info "  - Zone pricings created: #{stats[:zone_pricings_created]}"
    Rails.logger.info "  - Zone pricings updated: #{stats[:zone_pricings_updated]}"
    Rails.logger.info "  - Time pricings created: #{stats[:time_pricings_created]}"
    Rails.logger.info "  - Corridors created: #{stats[:corridors_created]}"
    Rails.logger.info "  - Corridors updated: #{stats[:corridors_updated]}"
    Rails.logger.info "  - Corridors deactivated (stale): #{stats[:corridors_deactivated]}"
    Rails.logger.info "  - Corridor conflicts skipped: #{stats[:corridor_conflicts]}"
    Rails.logger.info "  - Validation warnings: #{stats[:validation_warnings].count}"
    Rails.logger.info "  - Validation errors: #{stats[:validation_errors].count}"
    Rails.logger.info "  - Errors: #{stats[:errors].count}"
    
    stats[:validation_warnings].each do |warning|
      Rails.logger.warn "    - #{warning}"
    end

    stats[:validation_errors].each do |error|
      Rails.logger.error "    - #{error}"
    end

    stats[:errors].each do |err|
      Rails.logger.error "    - #{err[:zone_code] || err[:file]}: #{err[:error]}"
    end
  end
end
