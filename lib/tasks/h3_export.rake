# frozen_string_literal: true

# =============================================================================
# H3 Zone Export Rake Task
# =============================================================================
# Exports all zones + H3 cells + pricing to a single h3_zones.yml per city.
# This becomes the new source of truth for zone boundaries and pricing.
#
# USAGE:
#   rails zones:h3_export[hyd]
# =============================================================================

namespace :zones do
  desc "Export all zones with H3 cells and pricing to h3_zones.yml"
  task :h3_export, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    CITY_FOLDER_MAP = {
      'hyd' => 'hyderabad',
      'blr' => 'bangalore',
      'mum' => 'mumbai',
      'del' => 'delhi',
      'chn' => 'chennai'
    }.freeze

    city_folder = CITY_FOLDER_MAP[city_code.downcase] || city_code.downcase
    vehicle_types = RoutePricing::VehicleCategories::ALL_VEHICLES
    time_bands = %w[morning afternoon evening]

    # Load vehicle defaults for fallback pricing
    defaults_path = Rails.root.join('config', 'zones', city_folder, 'vehicle_defaults.yml')
    vehicle_defaults = File.exist?(defaults_path) ? YAML.load_file(defaults_path) : {}
    global_time_rates = vehicle_defaults['global_time_rates'] || {}

    zones = Zone.for_city(city_code).order(:zone_code)
    puts "Exporting #{zones.count} zones for #{city_code}..."

    zone_data = {}

    zones.each do |zone|
      # Fetch H3 R7 cells
      h3_cells = ZoneH3Mapping.where(zone_id: zone.id).pluck(:h3_index_r7).uniq.sort

      if h3_cells.empty?
        puts "  WARN: #{zone.zone_code} has no H3 cells, skipping"
        next
      end

      # Fetch existing pricing
      zone_pricings = ZoneVehiclePricing.where(zone_id: zone.id, active: true)
                                         .includes(:time_pricings)
                                         .index_by(&:vehicle_type)

      # Build pricing hash for all vehicles × time bands
      pricing = {}
      type_mult = Zone::DEFAULT_ZONE_MULTIPLIERS[zone.zone_type] || 1.0

      time_bands.each do |band|
        band_pricing = {}

        vehicle_types.each do |vt|
          zvp = zone_pricings[vt]

          if zvp
            # Check for time-specific override
            tp = zvp.time_pricings.find { |t| t.time_band == band && t.active? }
            if tp
              base_val = tp.base_fare_paise
              rate_val = tp.per_km_rate_paise
            else
              base_val = zvp.base_fare_paise
              rate_val = zvp.per_km_rate_paise
            end

            # Detect placeholder values (5000/1000) and replace with proper defaults
            if base_val == 5000 && rate_val == 1000
              defaults = global_time_rates.dig(band, vt)
              if defaults
                base_val = (defaults['base'] * type_mult).round
                rate_val = (defaults['rate'] * type_mult).round
              end
            end

            band_pricing[vt] = { 'base' => base_val, 'rate' => rate_val }
          else
            # Generate from global_time_rates × zone_type multiplier
            defaults = global_time_rates.dig(band, vt)
            if defaults
              band_pricing[vt] = {
                'base' => (defaults['base'] * type_mult).round,
                'rate' => (defaults['rate'] * type_mult).round
              }
            else
              band_pricing[vt] = { 'base' => 5000, 'rate' => 1000 }
            end
          end
        end

        pricing[band] = band_pricing
      end

      zone_data[zone.zone_code] = {
        'name' => zone.name,
        'zone_type' => zone.zone_type || 'default',
        'priority' => zone.priority || 10,
        'active' => zone.active?,
        'auto_generated' => zone.auto_generated? || false,
        'h3_cells_r7' => h3_cells,
        'pricing' => pricing
      }

      puts "  #{zone.zone_code}: #{h3_cells.size} cells, #{zone_pricings.size} vehicle pricings (#{zone_pricings.size > 0 ? 'DB' : 'defaults'})"
    end

    # Build output YAML
    output = {
      'city_code' => city_code,
      'version' => '1.0',
      'generated_at' => Time.current.iso8601,
      'zones' => zone_data
    }

    output_path = Rails.root.join('config', 'zones', city_folder, 'h3_zones.yml')
    File.write(output_path, output.to_yaml)

    puts "\nExported #{zone_data.size} zones to #{output_path}"
    puts "  Zones with DB pricing: #{zone_data.count { |_, z| z['pricing']['morning'].values.any? { |v| v['base'] > 0 } }}"
    puts "  Total H3 R7 cells: #{zone_data.sum { |_, z| z['h3_cells_r7'].size }}"
  end
end
