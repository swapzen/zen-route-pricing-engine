# frozen_string_literal: true

# =============================================================================
# H3 Zone Config Loader
# =============================================================================
# Reads h3_zones.yml → syncs everything to DB:
#   - Zones (create/update with auto-computed bbox from H3 cells)
#   - H3 mappings (ZoneH3Mapping per R7 cell, expand to R8)
#   - Pricing (ZoneVehiclePricing + ZoneVehicleTimePricing per vehicle × band)
#   - PricingConfig city defaults from vehicle_defaults.yml
#   - InterZoneConfig from vehicle_defaults.yml inter_zone_formula
#   - Deactivates zones in DB that are no longer in YAML
#   - Invalidates H3ZoneResolver cache
#
# USAGE:
#   H3ZoneConfigLoader.new('hyd').sync!
#   H3ZoneConfigLoader.new('hyd').sync!(force_pricing: true)
# =============================================================================

class H3ZoneConfigLoader
  include ConfigLoaderShared

  attr_reader :city_code, :stats

  def initialize(city_code)
    @city_code = city_code.to_s.downcase
    @stats = {
      zones_created: 0, zones_updated: 0, zones_deactivated: 0,
      h3_mappings_created: 0, h3_mappings_removed: 0,
      pricings_created: 0, pricings_updated: 0,
      time_pricings_created: 0, time_pricings_updated: 0,
      city_configs_created: 0, inter_zone_config_created: false,
      errors: []
    }
  end

  def sync!(force_pricing: false)
    h3_config = load_h3_zones
    return { success: false, error: "h3_zones.yml not found for #{city_code}" } unless h3_config

    vehicle_defaults = load_vehicle_defaults

    Rails.logger.info "[H3ZoneConfigLoader] Starting sync for #{city_code} (#{h3_config['zones']&.size || 0} zones)..."

    ActiveRecord::Base.transaction do
      yaml_zone_codes = sync_zones!(h3_config['zones'] || {}, force_pricing: force_pricing)
      deactivate_stale_zones!(yaml_zone_codes)
      seed_city_configs!(vehicle_defaults) if vehicle_defaults
      seed_distance_slabs!(vehicle_defaults) if vehicle_defaults
      seed_inter_zone_config!(vehicle_defaults) if vehicle_defaults
      seed_zone_operational_defaults!
      seed_weather_config_defaults!
      sync_corridors!(force: force_pricing)
    end

    # Rebuild H3 in-memory maps + compute boundaries outside transaction
    rebuild_h3_maps!
    compute_boundaries!

    log_results
    { success: true, stats: stats }
  rescue StandardError => e
    Rails.logger.error "[H3ZoneConfigLoader] Sync failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    { success: false, error: e.message, backtrace: e.backtrace.first(5) }
  end

  private

  # ---------------------------------------------------------------------------
  # Zone sync
  # ---------------------------------------------------------------------------
  def sync_zones!(zones_hash, force_pricing: false)
    yaml_zone_codes = []

    zones_hash.each do |zone_code, zone_data|
      yaml_zone_codes << zone_code
      sync_single_zone(zone_code, zone_data, force_pricing: force_pricing)
    end

    yaml_zone_codes
  end

  def sync_single_zone(zone_code, data, force_pricing: false)
    h3_cells = data['h3_cells_r7'] || []
    return if h3_cells.empty?

    # Compute bbox from H3 cell coordinates
    bbox = compute_bbox_from_h3_cells(h3_cells)

    zone = Zone.find_or_initialize_by(city: city_code, zone_code: zone_code)
    was_new = zone.new_record?

    zone.assign_attributes(
      name: data['name'] || zone_code.titleize,
      zone_type: data['zone_type'] || 'default',
      priority: data['priority'] || default_priority_for_type(data['zone_type']),
      status: data['active'] != false,
      auto_generated: data['auto_generated'] || false,
      lat_min: bbox[:lat_min],
      lat_max: bbox[:lat_max],
      lng_min: bbox[:lng_min],
      lng_max: bbox[:lng_max]
    )

    if zone.changed? || was_new
      zone.save!
      was_new ? stats[:zones_created] += 1 : stats[:zones_updated] += 1
    end

    sync_h3_mappings!(zone, h3_cells)
    sync_zone_pricing!(zone, data['pricing'] || {}, force: force_pricing)
  rescue StandardError => e
    stats[:errors] << { zone_code: zone_code, error: e.message }
    Rails.logger.error "[H3ZoneConfigLoader] Error syncing zone #{zone_code}: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # H3 mapping sync
  # ---------------------------------------------------------------------------
  def sync_h3_mappings!(zone, h3_cells)
    existing_r7s = ZoneH3Mapping.where(zone_id: zone.id).pluck(:h3_index_r7)
    new_r7s = h3_cells - existing_r7s
    stale_r7s = existing_r7s - h3_cells

    # Remove stale mappings
    if stale_r7s.any?
      ZoneH3Mapping.where(zone_id: zone.id, h3_index_r7: stale_r7s).delete_all
      stats[:h3_mappings_removed] += stale_r7s.size
    end

    # Create new mappings
    new_r7s.each do |r7_hex|
      r7_int = r7_hex.to_i(16)
      # Compute a representative R8 child
      r8_hex = begin
        r8_children = H3.children(r7_int, 8)
        r8_children.first&.to_s(16)
      rescue StandardError
        nil
      end

      # Check boundary
      existing_other = ZoneH3Mapping.where(h3_index_r7: r7_hex, city_code: city_code)
                                     .where.not(zone_id: zone.id).exists?

      ZoneH3Mapping.create!(
        zone: zone,
        h3_index_r7: r7_hex,
        h3_index_r8: r8_hex,
        city_code: city_code,
        is_boundary: existing_other,
        serviceable: true
      )
      stats[:h3_mappings_created] += 1

      # Mark existing mappings for same R7 as boundary
      if existing_other
        ZoneH3Mapping.where(h3_index_r7: r7_hex, city_code: city_code)
                     .where.not(zone_id: zone.id)
                     .update_all(is_boundary: true)
      end
    end

    # Update zone's H3 index arrays
    zone_r7s = ZoneH3Mapping.where(zone_id: zone.id).pluck(:h3_index_r7).uniq
    zone.update_columns(h3_indexes_r7: zone_r7s)
  end

  # ---------------------------------------------------------------------------
  # Pricing sync
  # ---------------------------------------------------------------------------
  def sync_zone_pricing!(zone, pricing_hash, force: false)
    return if pricing_hash.empty?

    VEHICLE_TYPES.each do |vehicle_type|
      # Use morning_rush rates as the base zone pricing (peak hour, most representative)
      # Fallback chain: morning_rush → morning → first available band
      base_rates = pricing_hash.dig('morning_rush', vehicle_type) ||
                   pricing_hash.dig('morning', vehicle_type) ||
                   TIME_BANDS.lazy.filter_map { |b| pricing_hash.dig(b, vehicle_type) }.first
      next unless base_rates

      zvp = ZoneVehiclePricing.find_or_initialize_by(
        city_code: city_code,
        zone: zone,
        vehicle_type: vehicle_type
      )

      was_new = zvp.new_record?

      if was_new || force
        zvp.assign_attributes(
          base_fare_paise: base_rates['base'] || 5000,
          per_km_rate_paise: base_rates['rate'] || 1000,
          per_min_rate_paise: base_rates['min_rate'] || 0,
          min_fare_paise: base_rates['base'] || 5000,
          base_distance_m: 1000,
          active: true
        )

        if zvp.changed? || was_new
          zvp.save!
          was_new ? stats[:pricings_created] += 1 : stats[:pricings_updated] += 1
        end
      end

      # Time band pricing
      TIME_BANDS.each do |band|
        rates = pricing_hash.dig(band, vehicle_type)
        next unless rates

        tp = ZoneVehicleTimePricing.find_or_initialize_by(
          zone_vehicle_pricing: zvp,
          time_band: band
        )

        tp_was_new = tp.new_record?

        if tp_was_new || force
          tp.assign_attributes(
            base_fare_paise: rates['base'] || 5000,
            per_km_rate_paise: rates['rate'] || 1000,
            per_min_rate_paise: rates['min_rate'] || 0,
            min_fare_paise: rates['base'] || 5000,
            active: true
          )

          if tp.changed? || tp_was_new
            tp.save!
            tp_was_new ? stats[:time_pricings_created] += 1 : stats[:time_pricings_updated] += 1
          end
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Deactivate stale zones
  # ---------------------------------------------------------------------------
  def deactivate_stale_zones!(yaml_zone_codes)
    stale_zones = Zone.for_city(city_code).where.not(zone_code: yaml_zone_codes).where(status: true)
    count = stale_zones.update_all(status: false)
    stats[:zones_deactivated] = count
    if count > 0
      Rails.logger.info "[H3ZoneConfigLoader] Deactivated #{count} zones not in h3_zones.yml"
    end
  end

  # ---------------------------------------------------------------------------
  # Seed PricingConfig city defaults
  # ---------------------------------------------------------------------------
  def seed_city_configs!(vehicle_defaults)
    global_time_rates = vehicle_defaults['global_time_rates'] || {}
    vehicles_config = vehicle_defaults['vehicles'] || {}

    VEHICLE_TYPES.each do |vehicle_type|
      pc = PricingConfig.find_or_initialize_by(
        city_code: city_code,
        vehicle_type: vehicle_type,
        active: true
      )

      next unless pc.new_record?

      # Use morning_rush as the base rate (peak hours), fallback to morning for backward compat
      base_rates = global_time_rates.dig('morning_rush', vehicle_type) ||
                   global_time_rates.dig('morning', vehicle_type) || {}
      vehicle_info = vehicles_config[vehicle_type] || {}

      pc.assign_attributes(
        base_fare_paise: vehicle_info['base_fare_paise'] || base_rates['base'] || 5000,
        per_km_rate_paise: base_rates['rate'] || 1000,
        per_min_rate_paise: base_rates['min_rate'] || 0,
        min_fare_paise: vehicle_info['base_fare_paise'] || base_rates['base'] || 5000,
        base_distance_m: vehicle_defaults['base_distance_m'] || 1000,
        timezone: 'Asia/Kolkata',
        vehicle_multiplier: 1.0,
        city_multiplier: 1.0,
        surge_multiplier: 1.0,
        version: 1,
        effective_from: Time.current,
        approval_status: 'approved'
      )

      pc.save!
      stats[:city_configs_created] += 1
    end
  end

  # ---------------------------------------------------------------------------
  # Seed PricingDistanceSlab from vehicle_defaults.yml slabs
  # ---------------------------------------------------------------------------
  def seed_distance_slabs!(vehicle_defaults)
    vehicles_config = vehicle_defaults['vehicles'] || {}

    vehicles_config.each do |vehicle_type, config|
      slabs = config['slabs']
      next unless slabs

      pc = PricingConfig.find_by(city_code: city_code, vehicle_type: vehicle_type, active: true)
      next unless pc

      slabs.each do |slab|
        min_m, max_m, rate = slab
        max_m = 999_999 if max_m.nil?

        ds = PricingDistanceSlab.find_or_initialize_by(
          pricing_config_id: pc.id,
          min_distance_m: min_m
        )
        ds.max_distance_m = max_m
        ds.per_km_rate_paise = rate

        if ds.new_record? || ds.changed?
          ds.save!
          stats[:distance_slabs_synced] = (stats[:distance_slabs_synced] || 0) + 1
        end
      end
    end
  rescue StandardError => e
    Rails.logger.warn "[H3ZoneConfigLoader] Distance slab seed skipped: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Seed InterZoneConfig
  # ---------------------------------------------------------------------------
  def seed_inter_zone_config!(vehicle_defaults)
    formula = vehicle_defaults['inter_zone_formula']
    return unless formula

    izc = InterZoneConfig.find_or_initialize_by(city_code: city_code, active: true)
    return unless izc.new_record?

    izc.assign_attributes(
      origin_weight: formula['origin_weight'] || 0.6,
      destination_weight: formula['destination_weight'] || 0.4,
      type_adjustments: formula['type_adjustments'] || {},
      active: true
    )
    izc.save!
    stats[:inter_zone_config_created] = true
  rescue StandardError => e
    # InterZoneConfig table may not exist yet (Phase 4 migration)
    Rails.logger.warn "[H3ZoneConfigLoader] InterZoneConfig seed skipped: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Post-sync: rebuild H3 maps + boundaries
  # ---------------------------------------------------------------------------
  def rebuild_h3_maps!
    RoutePricing::Services::H3ZoneResolver.invalidate!(city_code)
    map_stats = RoutePricing::Services::H3ZoneResolver.build_city_map(city_code)
    Rails.logger.info "[H3ZoneConfigLoader] H3 maps rebuilt: #{map_stats[:r7]} R7, #{map_stats[:r8]} R8"
  rescue StandardError => e
    Rails.logger.warn "[H3ZoneConfigLoader] H3 map rebuild failed: #{e.message}"
  end

  def compute_boundaries!
    RoutePricing::Services::ZoneBoundaryComputer.compute_for_city!(city_code)
  rescue StandardError => e
    Rails.logger.warn "[H3ZoneConfigLoader] Boundary computation failed: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Seed zone operational defaults (min fare overrides, cancellation rates)
  # ---------------------------------------------------------------------------
  def seed_zone_operational_defaults!
    # Min fare multipliers by zone_type (Phase 4)
    min_fare_multipliers = {
      'tech_corridor' => 1.2,
      'business_cbd' => 1.3,
      'airport_logistics' => 1.1
    }

    # Default cancellation rates by zone_type (Phase 6)
    cancellation_defaults = {
      'tech_corridor' => 3.0,
      'business_cbd' => 8.0,
      'airport_logistics' => 5.0,
      'residential_growth' => 12.0,
      'residential_dense' => 7.0,
      'residential_mixed' => 8.0,
      'industrial' => 10.0,
      'outer_ring' => 15.0,
      'premium_residential' => 6.0,
      'traditional_commercial' => 9.0,
      'heritage_commercial' => 9.0
    }

    zones = Zone.for_city(city_code).active
    return if zones.empty?

    # Only seed if columns exist
    has_min_fare = Zone.column_names.include?('min_fare_overrides')
    has_cancel = Zone.column_names.include?('cancellation_rate_pct')

    zones.find_each do |zone|
      updates = {}

      # Seed min fare overrides (only if null)
      if has_min_fare && zone.min_fare_overrides.nil?
        multiplier = min_fare_multipliers[zone.zone_type]
        if multiplier
          overrides = {}
          VEHICLE_TYPES.each do |vt|
            pc = PricingConfig.find_by(city_code: city_code, vehicle_type: vt, active: true)
            next unless pc
            overrides[vt] = (pc.base_fare_paise * multiplier).round
          end
          updates[:min_fare_overrides] = overrides if overrides.any?
        end
      end

      # Seed cancellation rate (only if null)
      if has_cancel && zone.cancellation_rate_pct.nil?
        rate = cancellation_defaults[zone.zone_type]
        updates[:cancellation_rate_pct] = rate if rate
      end

      zone.update_columns(updates) if updates.any?
    end
  rescue StandardError => e
    Rails.logger.warn "[H3ZoneConfigLoader] Zone operational defaults seed skipped: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Seed weather config defaults on PricingConfigs
  # ---------------------------------------------------------------------------
  def seed_weather_config_defaults!
    return unless PricingConfig.column_names.include?('weather_multipliers')

    default_weather = {
      'clear' => 1.0,
      'clouds' => 1.0,
      'drizzle' => 1.05,
      'rain_light' => 1.10,
      'rain_heavy' => 1.20,
      'fog' => 1.08,
      'storm' => 1.25,
      'extreme_heat' => 1.05
    }

    PricingConfig.where(city_code: city_code, active: true, weather_multipliers: nil).find_each do |pc|
      pc.update_columns(weather_multipliers: default_weather)
    end
  rescue StandardError => e
    Rails.logger.warn "[H3ZoneConfigLoader] Weather config defaults seed skipped: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  def compute_bbox_from_h3_cells(h3_cells)
    lats = []
    lngs = []

    h3_cells.each do |r7_hex|
      r7_int = r7_hex.to_i(16)
      begin
        boundary = H3.to_boundary(r7_int)
        boundary.each do |lat, lng|
          lats << lat
          lngs << lng
        end
      rescue StandardError
        # Skip cells with invalid H3 indexes
      end
    end

    return { lat_min: 0, lat_max: 0, lng_min: 0, lng_max: 0 } if lats.empty?

    {
      lat_min: lats.min,
      lat_max: lats.max,
      lng_min: lngs.min,
      lng_max: lngs.max
    }
  end

  # default_priority_for_type, city_folder, load_vehicle_defaults
  # are inherited from ConfigLoaderShared

  def load_h3_zones
    path = Rails.root.join('config', 'zones', city_folder, 'h3_zones.yml')
    return nil unless File.exist?(path)
    YAML.load_file(path)
  end

  def log_results
    Rails.logger.info "[H3ZoneConfigLoader] Sync complete for #{city_code}:"
    stats.each do |key, value|
      next if key == :errors
      Rails.logger.info "  #{key}: #{value}"
    end
    stats[:errors].each do |err|
      Rails.logger.error "  ERROR: #{err[:zone_code]}: #{err[:error]}"
    end
  end
end
