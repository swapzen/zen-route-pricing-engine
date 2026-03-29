# frozen_string_literal: true

module RoutePricing
  module Services
    class InterZoneDetector
      # Auto-detects adjacent zone pairs using H3 k-ring adjacency and generates
      # inter-zone (corridor) pricing via weighted average of intra-zone rates.
      #
      # Algorithm:
      # 1. Build cell_zone_map: R7 hex → zone_id from zone_h3_mappings (serviceable only)
      # 2. For each boundary cell: k_ring(h3, 1) → 6 neighbors
      # 3. If neighbor belongs to different zone → record pair
      # 4. Deduplicate (normalize by sorting IDs)
      # 5. Generate pricing: weighted average (60% origin, 40% dest) with type adjustments

      VEHICLE_TYPES = RoutePricing::VehicleCategories::ALL_VEHICLES
      TIME_BANDS = %w[early_morning morning_rush midday afternoon evening_rush night weekend_day weekend_night].freeze

      def initialize(city_code)
        @city_code = city_code
        @config = load_inter_zone_config
      end

      # Detect adjacent pairs + generate corridor pricing
      def detect_and_generate!
        pairs = detect_adjacent_zones
        stats = { pairs_detected: pairs.size, corridors_created: 0, corridors_skipped: 0 }

        # Remove previous auto-generated corridors for idempotent re-runs
        removed = ZonePairVehiclePricing.where(city_code: @city_code, auto_generated: true).delete_all
        stats[:previous_removed] = removed

        zone_cache = Zone.for_city(@city_code).active.index_by(&:id)

        pairs.each do |zone_a_id, zone_b_id|
          zone_a = zone_cache[zone_a_id]
          zone_b = zone_cache[zone_b_id]
          next unless zone_a && zone_b

          # Skip if manual corridor exists
          if manual_corridor_exists?(zone_a_id, zone_b_id)
            stats[:corridors_skipped] += 1
            next
          end

          created = generate_corridor_pricing(zone_a, zone_b)
          stats[:corridors_created] += created
        end

        Rails.logger.info "[InterZoneDetector] #{@city_code}: #{stats}"
        stats
      end

      # Dry run: just return adjacent zone pairs
      def detect_adjacent_zones
        cell_zone_map = build_cell_zone_map
        pairs = Set.new

        boundary_cells = ZoneH3Mapping.for_city(@city_code)
                                      .where(is_boundary: true, serviceable: true)

        boundary_cells.find_each do |mapping|
          h3_int = mapping.h3_index_r7.to_i(16)
          neighbors = H3.k_ring(h3_int, 1) - [h3_int]

          neighbors.each do |neighbor_int|
            neighbor_hex = neighbor_int.to_s(16)
            neighbor_zone_id = cell_zone_map[neighbor_hex]

            next unless neighbor_zone_id
            next if neighbor_zone_id == mapping.zone_id

            # Normalize pair by sorting IDs
            pair = [mapping.zone_id, neighbor_zone_id].sort
            pairs.add(pair)
          end
        end

        pairs.to_a
      end

      private

      def build_cell_zone_map
        map = {}
        ZoneH3Mapping.for_city(@city_code)
                     .serviceable
                     .pluck(:h3_index_r7, :zone_id)
                     .each { |hex, zone_id| map[hex] = zone_id }
        map
      end

      def manual_corridor_exists?(zone_a_id, zone_b_id)
        ZonePairVehiclePricing.where(
          city_code: @city_code,
          auto_generated: [false, nil]
        ).where(
          "(from_zone_id = ? AND to_zone_id = ?) OR (from_zone_id = ? AND to_zone_id = ?)",
          zone_a_id, zone_b_id, zone_b_id, zone_a_id
        ).exists?
      end

      def generate_corridor_pricing(zone_a, zone_b)
        origin_weight = @config[:origin_weight]
        dest_weight = @config[:destination_weight]
        type_adjustments = @config[:type_adjustments]
        created = 0

        a_pricing = load_zone_pricing(zone_a.id)
        b_pricing = load_zone_pricing(zone_b.id)

        VEHICLE_TYPES.each do |vehicle_type|
          TIME_BANDS.each do |time_band|
            a_rates = find_rates(a_pricing, vehicle_type, time_band)
            b_rates = find_rates(b_pricing, vehicle_type, time_band)

            next unless a_rates || b_rates
            a_rates ||= b_rates
            b_rates ||= a_rates

            # Weighted average
            base_fare = (a_rates[:base_fare] * origin_weight + b_rates[:base_fare] * dest_weight).round
            per_km = (a_rates[:per_km] * origin_weight + b_rates[:per_km] * dest_weight).round
            min_fare = (a_rates[:min_fare] * origin_weight + b_rates[:min_fare] * dest_weight).round
            per_min = (a_rates[:per_min] * origin_weight + b_rates[:per_min] * dest_weight).round

            # Apply zone-type adjustment
            adjustment = lookup_type_adjustment(zone_a.zone_type, zone_b.zone_type, time_band, type_adjustments)
            base_fare = (base_fare * adjustment).round
            per_km = (per_km * adjustment).round
            min_fare = (min_fare * adjustment).round

            ZonePairVehiclePricing.create!(
              city_code: @city_code,
              from_zone_id: zone_a.id,
              to_zone_id: zone_b.id,
              vehicle_type: vehicle_type,
              time_band: time_band,
              base_fare_paise: base_fare,
              per_km_rate_paise: per_km,
              min_fare_paise: min_fare,
              per_min_rate_paise: per_min,
              directional: false,
              active: true,
              auto_generated: true
            )
            created += 1
          end
        end

        created
      end

      def load_zone_pricing(zone_id)
        zone_pricings = ZoneVehiclePricing.where(zone_id: zone_id, active: true).includes(:time_pricings)
        zone_pricings.index_by(&:vehicle_type)
      end

      def find_rates(pricing_hash, vehicle_type, time_band)
        zvp = pricing_hash[vehicle_type]
        return nil unless zvp

        # Try time-band specific rates first
        time_pricing = zvp.time_pricings.find { |tp| tp.time_band == time_band && tp.active? }

        if time_pricing
          {
            base_fare: time_pricing.base_fare_paise || 0,
            per_km: time_pricing.per_km_rate_paise || 0,
            min_fare: time_pricing.min_fare_paise || 0,
            per_min: time_pricing.per_min_rate_paise || 0
          }
        else
          {
            base_fare: zvp.base_fare_paise || 0,
            per_km: zvp.per_km_rate_paise || 0,
            min_fare: zvp.min_fare_paise || 0,
            per_min: zvp.per_min_rate_paise || 0
          }
        end
      end

      def lookup_type_adjustment(from_type, to_type, time_band, type_adjustments)
        # Try specific pair first
        key = "#{from_type}_to_#{to_type}"
        adj = type_adjustments.dig(key, time_band)
        return adj if adj

        # Try wildcard patterns
        any_to = "any_to_#{to_type}"
        adj = type_adjustments.dig(any_to, time_band)
        return adj if adj

        from_any = "#{from_type}_to_any"
        adj = type_adjustments.dig(from_any, time_band)
        return adj if adj

        # Default
        type_adjustments.dig('default', time_band) || 1.0
      end

      def load_inter_zone_config
        # DB first
        db_config = load_inter_zone_from_db
        return db_config if db_config

        # YAML fallback
        path = find_vehicle_defaults_path
        return default_config unless path && File.exist?(path)

        data = YAML.load_file(path)
        formula = data['inter_zone_formula'] || {}

        {
          origin_weight: formula['origin_weight'] || 0.6,
          destination_weight: formula['destination_weight'] || 0.4,
          type_adjustments: (formula['type_adjustments'] || {}).deep_stringify_keys
        }
      end

      def load_inter_zone_from_db
        return nil unless defined?(InterZoneConfig) && InterZoneConfig.table_exists?

        record = InterZoneConfig.active.find_by(city_code: @city_code.to_s.downcase)
        return nil unless record

        {
          origin_weight: record.origin_weight,
          destination_weight: record.destination_weight,
          type_adjustments: (record.type_adjustments || {}).deep_stringify_keys
        }
      rescue StandardError
        nil
      end

      def find_vehicle_defaults_path
        city_folder = city_folder_name(@city_code)
        Rails.root.join('config', 'zones', city_folder, 'vehicle_defaults.yml')
      end

      def city_folder_name(city_code)
        {
          'hyd' => 'hyderabad',
          'blr' => 'bangalore',
          'mum' => 'mumbai',
          'del' => 'delhi',
          'chn' => 'chennai'
        }[city_code.to_s.downcase] || city_code.to_s.downcase
      end

      def default_config
        {
          origin_weight: 0.6,
          destination_weight: 0.4,
          type_adjustments: { 'default' => { 'morning' => 1.0, 'afternoon' => 1.0, 'evening' => 1.0 } }
        }
      end
    end
  end
end
