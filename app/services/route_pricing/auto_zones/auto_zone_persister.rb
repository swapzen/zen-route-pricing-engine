# frozen_string_literal: true

module RoutePricing
  module AutoZones
    class AutoZonePersister
      # Persists clustered auto-zones to database:
      # - Creates Zone records (auto_generated: true)
      # - Creates ZoneH3Mapping for each cell
      # - Creates default ZoneVehiclePricing from vehicle_defaults.yml
      # - Idempotent: removes previous auto-zones of same version first

      VEHICLE_TYPES = RoutePricing::VehicleCategories::ALL_VEHICLES
      TIME_BANDS = %w[early_morning morning_rush midday afternoon evening_rush night weekend_day weekend_night].freeze

      # Priority offset: auto-zones get lower priority than manual zones
      AUTO_ZONE_PRIORITY_OFFSET = -10

      def initialize(clusters:, city_code:, generation_version:)
        @clusters = clusters
        @city_code = city_code
        @generation_version = generation_version
        @stats = { zones_created: 0, cells_mapped: 0, pricing_records: 0 }
      end

      def persist!
        ActiveRecord::Base.transaction do
          remove_previous_version!
          @clusters.each { |cluster| persist_cluster(cluster) }
        end

        Rails.logger.info "[AutoZonePersister] Created #{@stats[:zones_created]} zones, " \
                          "#{@stats[:cells_mapped]} cell mappings, #{@stats[:pricing_records]} pricing records"
        @stats
      end

      private

      def remove_previous_version!
        old_zones = Zone.for_city(@city_code)
                        .where(auto_generated: true, generation_version: @generation_version)

        count = old_zones.count
        if count > 0
          # ZoneH3Mapping, ZoneVehiclePricing etc. cascade via dependent: :destroy
          old_zones.destroy_all
          Rails.logger.info "[AutoZonePersister] Removed #{count} previous v#{@generation_version} auto-zones"
        end
      end

      def persist_cluster(cluster)
        zone = create_zone(cluster)
        create_h3_mappings(zone, cluster[:cells])
        create_default_pricing(zone)
        compute_boundary(zone)
        @stats[:zones_created] += 1
      end

      def create_zone(cluster)
        bounds = cluster[:bounds]
        base_priority = default_priority_for_type(cluster[:zone_type])

        Zone.create!(
          city: @city_code,
          zone_code: cluster[:zone_code],
          name: humanize_zone_code(cluster[:zone_code]),
          zone_type: cluster[:zone_type],
          status: true,
          auto_generated: true,
          generation_version: @generation_version,
          cell_count: cluster[:cells].size,
          parent_zone_code: cluster[:parent_zone_code],
          lat_min: bounds[:lat_min],
          lat_max: bounds[:lat_max],
          lng_min: bounds[:lng_min],
          lng_max: bounds[:lng_max],
          priority: base_priority + AUTO_ZONE_PRIORITY_OFFSET
        )
      end

      def create_h3_mappings(zone, cells)
        h3_indexes = []

        cells.each do |cell|
          # Compute R8 hex from the cell center point
          h3_r8 = H3.from_geo_coordinates([cell[:lat], cell[:lng]], 8).to_s(16)

          ZoneH3Mapping.create!(
            zone: zone,
            h3_index_r7: cell[:h3_index_r7],
            h3_index_r8: h3_r8,
            city_code: @city_code,
            is_boundary: false
          )
          h3_indexes << cell[:h3_index_r7]
          @stats[:cells_mapped] += 1
        end

        zone.update!(h3_indexes_r7: h3_indexes)
      end

      def create_default_pricing(zone)
        # Try inheriting from parent zone first
        if zone.parent_zone_code.present? && inherit_from_parent(zone)
          return
        end

        # Fallback: city defaults with zone-type multiplier
        create_pricing_from_defaults(zone)
      end

      def inherit_from_parent(zone)
        parent = Zone.for_city(@city_code).find_by(zone_code: zone.parent_zone_code)
        return false unless parent

        parent_pricings = ZoneVehiclePricing.where(zone_id: parent.id, active: true)
                                            .includes(:time_pricings)
        return false if parent_pricings.empty?

        # Zone-type multiplier ratio: auto-zone type vs parent type
        auto_mult = Zone::DEFAULT_ZONE_MULTIPLIERS[zone.zone_type] || 1.0
        parent_mult = Zone::DEFAULT_ZONE_MULTIPLIERS[parent.zone_type] || 1.0
        ratio = parent_mult > 0 ? auto_mult / parent_mult : 1.0

        parent_pricings.each do |pvp|
          zone_pricing = ZoneVehiclePricing.create!(
            city_code: @city_code,
            zone: zone,
            vehicle_type: pvp.vehicle_type,
            base_fare_paise: (pvp.base_fare_paise * ratio).round,
            per_km_rate_paise: (pvp.per_km_rate_paise * ratio).round,
            per_min_rate_paise: ((pvp.per_min_rate_paise || 0) * ratio).round,
            min_fare_paise: (pvp.min_fare_paise * ratio).round,
            base_distance_m: pvp.base_distance_m || 1000,
            active: true
          )
          @stats[:pricing_records] += 1

          pvp.time_pricings.select(&:active?).each do |ptp|
            ZoneVehicleTimePricing.create!(
              zone_vehicle_pricing: zone_pricing,
              time_band: ptp.time_band,
              base_fare_paise: (ptp.base_fare_paise * ratio).round,
              per_km_rate_paise: (ptp.per_km_rate_paise * ratio).round,
              per_min_rate_paise: ((ptp.per_min_rate_paise || 0) * ratio).round,
              min_fare_paise: (ptp.min_fare_paise * ratio).round,
              active: true
            )
            @stats[:pricing_records] += 1
          end
        end

        true
      end

      def create_pricing_from_defaults(zone)
        global_rates = load_global_time_rates
        type_mult = Zone::DEFAULT_ZONE_MULTIPLIERS[zone.zone_type] || 1.0

        VEHICLE_TYPES.each do |vehicle_type|
          morning_rates = global_rates.dig('morning', vehicle_type) || { 'base' => 5000, 'rate' => 1000 }

          zone_pricing = ZoneVehiclePricing.create!(
            city_code: @city_code,
            zone: zone,
            vehicle_type: vehicle_type,
            base_fare_paise: ((morning_rates['base'] || 5000) * type_mult).round,
            per_km_rate_paise: ((morning_rates['rate'] || 1000) * type_mult).round,
            per_min_rate_paise: ((morning_rates['min_rate'] || 0) * type_mult).round,
            min_fare_paise: ((morning_rates['base'] || 5000) * type_mult).round,
            base_distance_m: 1000,
            active: true
          )
          @stats[:pricing_records] += 1

          TIME_BANDS.each do |time_band|
            rates = global_rates.dig(time_band, vehicle_type)
            next unless rates

            ZoneVehicleTimePricing.create!(
              zone_vehicle_pricing: zone_pricing,
              time_band: time_band,
              base_fare_paise: ((rates['base'] || 5000) * type_mult).round,
              per_km_rate_paise: ((rates['rate'] || 1000) * type_mult).round,
              per_min_rate_paise: ((rates['min_rate'] || 0) * type_mult).round,
              min_fare_paise: ((rates['base'] || 5000) * type_mult).round,
              active: true
            )
            @stats[:pricing_records] += 1
          end
        end
      end

      def load_global_time_rates
        @global_time_rates ||= begin
          path = Rails.root.join('config', 'zones', city_folder_name, 'vehicle_defaults.yml')
          if File.exist?(path)
            data = YAML.load_file(path)
            data['global_time_rates'] || {}
          else
            {}
          end
        end
      end

      def compute_boundary(zone)
        RoutePricing::Services::ZoneBoundaryComputer.new(zone).compute!
      rescue StandardError => e
        Rails.logger.warn "[AutoZonePersister] Boundary computation failed for #{zone.zone_code}: #{e.message}"
      end

      def default_priority_for_type(zone_type)
        case zone_type
        when 'tech_corridor'          then 20
        when 'business_cbd'           then 18
        when 'heritage_commercial'    then 18
        when 'premium_residential'    then 16
        when 'airport_logistics'      then 15
        when 'traditional_commercial' then 14
        when 'industrial'             then 12
        when 'residential_dense'      then 10
        when 'residential_mixed'      then 10
        when 'residential_growth'     then 8
        when 'outer_ring'             then 5
        else                                10
        end
      end

      def humanize_zone_code(code)
        # "auto_residential_dense_001" → "Auto Residential Dense 001"
        code.split('_').map(&:capitalize).join(' ')
      end

      def city_folder_name
        {
          'hyd' => 'hyderabad',
          'blr' => 'bangalore',
          'mum' => 'mumbai',
          'del' => 'delhi',
          'chn' => 'chennai'
        }[@city_code.to_s.downcase] || @city_code.to_s.downcase
      end
    end
  end
end
