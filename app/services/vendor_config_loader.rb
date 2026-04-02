# frozen_string_literal: true

# =============================================================================
# Vendor Config Loader Service
# =============================================================================
# Loads vendor rate cards from YAML files and syncs to database.
# Pattern mirrors ZoneConfigLoader for consistency.
#
# USAGE:
#   VendorConfigLoader.new('vendor_name', 'hyd').sync!
# =============================================================================

class VendorConfigLoader
  attr_reader :vendor_code, :city_code, :stats

  VEHICLE_TYPES = RoutePricing::VehicleCategories::ALL_VEHICLES
  TIME_BANDS = %w[early_morning morning_rush midday afternoon evening_rush night weekend_day weekend_night].freeze

  def initialize(vendor_code, city_code)
    @vendor_code = vendor_code.downcase
    @city_code = city_code.downcase
    @stats = {
      created: 0,
      updated: 0,
      skipped: 0,
      errors: []
    }
  end

  def sync!
    config = load_config
    return { success: false, error: "No config found for vendor: #{vendor_code}, city: #{city_code}" } unless config

    Rails.logger.info "[VendorConfigLoader] Starting sync for #{vendor_code}/#{city_code}..."

    rates = config['rates'] || {}
    surge_cap = config['surge_cap'] || 2.0

    ActiveRecord::Base.transaction do
      # Sync time-band-specific rates
      TIME_BANDS.each do |time_band|
        band_rates = rates[time_band] || {}
        VEHICLE_TYPES.each do |vehicle_type|
          vehicle_rates = band_rates[vehicle_type]
          next unless vehicle_rates

          sync_rate_card(vehicle_type, time_band, vehicle_rates, surge_cap)
        end
      end

      # Sync all-day rates if present
      all_day_rates = rates['all_day'] || {}
      VEHICLE_TYPES.each do |vehicle_type|
        vehicle_rates = all_day_rates[vehicle_type]
        next unless vehicle_rates

        sync_rate_card(vehicle_type, nil, vehicle_rates, surge_cap)
      end
    end

    log_results
    { success: true, stats: stats }
  rescue StandardError => e
    Rails.logger.error "[VendorConfigLoader] Sync failed: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def load_config
    config_path = Rails.root.join('config', 'vendors', "#{vendor_code}_#{city_code}.yml")
    # Also try generic vendor file
    config_path = Rails.root.join('config', 'vendors', "#{vendor_code}_enterprise.yml") unless File.exist?(config_path)

    return nil unless File.exist?(config_path)

    data = YAML.load_file(config_path)
    # Verify city matches
    return nil if data['city_code'] && data['city_code'] != city_code

    data
  rescue StandardError => e
    Rails.logger.error "[VendorConfigLoader] Failed to load config: #{e.message}"
    nil
  end

  def sync_rate_card(vehicle_type, time_band, rates, surge_cap)
    card = VendorRateCard.find_or_initialize_by(
      vendor_code: vendor_code,
      city_code: city_code,
      vehicle_type: vehicle_type,
      time_band: time_band,
      version: 1
    )

    was_new = card.new_record?

    card.assign_attributes(
      base_fare_paise: rates['base'] || 0,
      per_km_rate_paise: rates['rate'] || 0,
      per_min_rate_paise: rates['min_rate'] || 0,
      min_fare_paise: rates['min_fare'] || rates['base'] || 0,
      free_km_m: rates['free_km_m'] || 1000,
      dead_km_rate_paise: rates['dead_km_rate'] || 0,
      surge_cap_multiplier: surge_cap,
      effective_from: Time.current,
      active: true
    )

    if card.changed?
      card.save!
      if was_new
        stats[:created] += 1
      else
        stats[:updated] += 1
      end
    else
      stats[:skipped] += 1
    end
  rescue StandardError => e
    stats[:errors] << { vehicle_type: vehicle_type, time_band: time_band, error: e.message }
    Rails.logger.error "[VendorConfigLoader] Error syncing #{vehicle_type}/#{time_band}: #{e.message}"
  end

  def log_results
    Rails.logger.info "[VendorConfigLoader] Sync complete for #{vendor_code}/#{city_code}:"
    Rails.logger.info "  - Created: #{stats[:created]}"
    Rails.logger.info "  - Updated: #{stats[:updated]}"
    Rails.logger.info "  - Skipped: #{stats[:skipped]}"
    Rails.logger.info "  - Errors: #{stats[:errors].count}"
  end
end
