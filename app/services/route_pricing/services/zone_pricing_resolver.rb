module RoutePricing
  module Services
    class ZonePricingResolver
      Result = Struct.new(
        :base_fare_paise, 
        :min_fare_paise, 
        :per_km_rate_paise, 
        :base_distance_m, 
        :source, 
        :pricing_mode,
        :zone_info,
        :zone_slabs,  # Zone-specific distance slabs (if available)
        # Industry-standard pricing configs (Cogoport/ShipX patterns)
        :fuel_surcharge_pct,           # FSC % from zone config
        :zone_multiplier,              # SLS multiplier from zone config
        :special_location_surcharge,   # Flat fee for special locations
        :oda_config,                   # ODA configuration for this route
        keyword_init: true
      )

      # Inter-zone formula weights (configurable)
      DEFAULT_ORIGIN_WEIGHT = 0.6
      DEFAULT_DESTINATION_WEIGHT = 0.4

      CITY_FILE_MAPPING = {
        'hyd' => 'hyderabad',
        'blr' => 'bangalore',
        'mum' => 'mumbai',
        'del' => 'delhi',
        'chn' => 'chennai',
        'pun' => 'pune'
      }.freeze

      INTER_ZONE_CACHE_TTL = 1.hour

      class << self
        def inter_zone_config_cache
          @inter_zone_config_cache ||= {}
        end

        def inter_zone_cache_timestamps
          @inter_zone_cache_timestamps ||= {}
        end

        def reset_inter_zone_config_cache!
          @inter_zone_config_cache = {}
          @inter_zone_cache_timestamps = {}
        end
      end

      def resolve(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, time_band: nil)
        # 1. Resolve Zones
        pickup_zone = find_zone(city_code, pickup_lat, pickup_lng)
        drop_zone = find_zone(city_code, drop_lat, drop_lng)
        inter_zone_config = load_inter_zone_config(city_code)
        
        # 2. Global Default Config (Fallback)
        global_config = cached_city_config(city_code, vehicle_type)
        
        # 3. Extract zone-level pricing configs (Industry standard patterns)
        zone_pricing_configs = extract_zone_pricing_configs(pickup_zone, drop_zone)
        
        # Defaults if global config missing
        defaults = {
          base_fare_paise: global_config&.base_fare_paise || 5000,
          min_fare_paise: global_config&.min_fare_paise || 4500,
          per_km_rate_paise: global_config&.per_km_rate_paise || 1000,
          base_distance_m: global_config&.base_distance_m || 1000,
          source: :city_default,
          pricing_mode: :slab,
          zone_info: { 
            pickup_zone: pickup_zone&.zone_code, 
            pickup_type: pickup_zone&.zone_type,
            drop_zone: drop_zone&.zone_code,
            drop_type: drop_zone&.zone_type,
            time_band: time_band
          },
          # Industry-standard configs from zone
          fuel_surcharge_pct: zone_pricing_configs[:fuel_surcharge_pct],
          zone_multiplier: zone_pricing_configs[:zone_multiplier],
          special_location_surcharge: zone_pricing_configs[:special_location_surcharge],
          oda_config: zone_pricing_configs[:oda_config]
        }

        # 3. Check Zone Pair Override (Corridor Pricing) - Time-Band Aware
        # Allow both inter-zone and intra-zone corridors (for premium routes like Route 10)
        if pickup_zone && drop_zone
          pair_pricing = cached_pair_pricing(city_code, pickup_zone.id, drop_zone.id, vehicle_type, time_band)
          if pair_pricing
             # Corridor pricing uses linear mode with explicit rates
             # Zone multipliers are bypassed (corridor rates are fully calibrated)
             zone_slabs = cached_zone_slabs(pickup_zone, vehicle_type)
             return Result.new(
               base_fare_paise: pair_pricing.base_fare_paise || defaults[:base_fare_paise],
               min_fare_paise: pair_pricing.min_fare_paise || defaults[:min_fare_paise],
               per_km_rate_paise: pair_pricing.per_km_rate_paise || defaults[:per_km_rate_paise],
               base_distance_m: defaults[:base_distance_m],
               source: :corridor_override,
               pricing_mode: :linear,
               zone_info: defaults[:zone_info],
               zone_slabs: zone_slabs,
               # Corridor pricing bypasses zone multipliers (rates are pre-calibrated)
               fuel_surcharge_pct: 0.0,
               zone_multiplier: 1.0,
               special_location_surcharge: 0,
               oda_config: { both_oda: false, surcharge_pct: 0 }
             )
          end
        end

        # 4. Check for Inter-Zone Formula (when both zones exist but no corridor)
        if pickup_zone && drop_zone && pickup_zone.id != drop_zone.id
          inter_zone_result = calculate_inter_zone_pricing(
            pickup_zone, drop_zone, vehicle_type, time_band, defaults, inter_zone_config
          )
          return inter_zone_result if inter_zone_result
        end

        # 5. Check Zone-Specific Override (with Time Awareness) - INTRA-ZONE pricing
        reference_zone = pickup_zone
        
        if reference_zone
          zone_pricing = cached_zone_pricing(city_code, reference_zone, vehicle_type)

          if zone_pricing
            # Fetch zone-specific slabs
            zone_slabs = cached_zone_slabs(reference_zone, vehicle_type)
            
            # 5a. Try time-specific pricing first
            if time_band.present?
              time_pricing = zone_pricing.time_pricings.detect { |tp| tp.active && tp.time_band == time_band }
              if time_pricing
                # Zone-specific time-band rates are pre-calibrated, so bypass zone multipliers
                zone_pricing_configs = extract_zone_pricing_configs(pickup_zone, drop_zone)
                return Result.new(
                  base_fare_paise: time_pricing.base_fare_paise,
                  min_fare_paise: time_pricing.min_fare_paise,
                  per_km_rate_paise: time_pricing.per_km_rate_paise,
                  base_distance_m: zone_pricing.base_distance_m,
                  source: :zone_time_override,
                  pricing_mode: zone_slabs.present? ? :zone_slab : :linear,
                  zone_info: defaults[:zone_info],
                  zone_slabs: zone_slabs,
                  # Zone-specific rates are pre-calibrated, so set zone_multiplier to 1.0
                  fuel_surcharge_pct: zone_pricing_configs[:fuel_surcharge_pct],
                  zone_multiplier: 1.0,  # Explicitly set to 1.0 to prevent double-counting
                  special_location_surcharge: zone_pricing_configs[:special_location_surcharge],
                  oda_config: zone_pricing_configs[:oda_config]
                )
              end
            end
            
            # 5b. Fallback to base zone pricing (time-neutral)
            # Zone-specific rates are pre-calibrated, so bypass zone multipliers
            zone_pricing_configs = extract_zone_pricing_configs(pickup_zone, drop_zone)
            return Result.new(
              base_fare_paise: zone_pricing.base_fare_paise,
              min_fare_paise: zone_pricing.min_fare_paise,
              per_km_rate_paise: zone_pricing.per_km_rate_paise,
              base_distance_m: zone_pricing.base_distance_m,
              source: :zone_override,
              pricing_mode: zone_slabs.present? ? :zone_slab : :linear,
              zone_info: defaults[:zone_info],
              zone_slabs: zone_slabs,
              # Zone-specific rates are pre-calibrated, so set zone_multiplier to 1.0
              fuel_surcharge_pct: zone_pricing_configs[:fuel_surcharge_pct],
              zone_multiplier: 1.0,  # Explicitly set to 1.0 to prevent double-counting
              special_location_surcharge: zone_pricing_configs[:special_location_surcharge],
              oda_config: zone_pricing_configs[:oda_config]
            )
          end
        end

        # 6. Return Default (with zone slabs if available)
        zone_slabs = pickup_zone ? cached_zone_slabs(pickup_zone, vehicle_type) : nil
        Result.new(defaults.merge(zone_slabs: zone_slabs))
      end

      private

      # =========================================================================
      # INTER-ZONE FORMULA
      # =========================================================================
      # Calculates pricing for zone pairs without explicit corridors
      # Uses weighted average of origin and destination zone rates
      # with adjustments based on zone type combinations
      def calculate_inter_zone_pricing(pickup_zone, drop_zone, vehicle_type, time_band, defaults, inter_zone_config)
        # Get pricing for both zones
        pickup_pricing = get_zone_time_pricing(pickup_zone, vehicle_type, time_band)
        drop_pricing = get_zone_time_pricing(drop_zone, vehicle_type, time_band)

        # Need at least one zone's pricing to calculate
        return nil unless pickup_pricing || drop_pricing

        # If only one zone has pricing, use it directly
        if pickup_pricing && !drop_pricing
          return build_inter_zone_result(pickup_pricing, pickup_pricing, 1.0, 0.0, 
                                         pickup_zone, drop_zone, vehicle_type, defaults, time_band)
        end

        if drop_pricing && !pickup_pricing
          return build_inter_zone_result(drop_pricing, drop_pricing, 0.0, 1.0,
                                         pickup_zone, drop_zone, vehicle_type, defaults, time_band)
        end

        # Get zone type adjustment factor
        adjustment = get_zone_type_adjustment(
          pickup_zone.zone_type,
          drop_zone.zone_type,
          time_band,
          inter_zone_config
        )

        origin_weight = inter_zone_config[:origin_weight] || DEFAULT_ORIGIN_WEIGHT
        destination_weight = inter_zone_config[:destination_weight] || DEFAULT_DESTINATION_WEIGHT

        # Build result with weighted average
        build_inter_zone_result(pickup_pricing, drop_pricing, origin_weight, destination_weight,
                               pickup_zone, drop_zone, vehicle_type, defaults, time_band, adjustment)
      end

      def get_zone_time_pricing(zone, vehicle_type, time_band)
        return nil unless zone

        zone_pricing = cached_zone_pricing(zone.city, zone, vehicle_type)
        return nil unless zone_pricing

        if time_band.present?
          time_pricing = zone_pricing.time_pricings.detect { |tp| tp.active && tp.time_band == time_band }
          return time_pricing if time_pricing
        end

        # Return base zone pricing as fallback
        zone_pricing
      end

      def build_inter_zone_result(pickup_pricing, drop_pricing, pickup_weight, drop_weight,
                                  pickup_zone, drop_zone, vehicle_type, defaults, time_band, adjustment = 1.0)
        # Weighted average calculation
        base_fare = (
          pickup_pricing.base_fare_paise * pickup_weight +
          drop_pricing.base_fare_paise * drop_weight
        ) * adjustment

        per_km_rate = (
          pickup_pricing.per_km_rate_paise * pickup_weight +
          drop_pricing.per_km_rate_paise * drop_weight
        ) * adjustment

        min_fare = (
          pickup_pricing.min_fare_paise * pickup_weight +
          drop_pricing.min_fare_paise * drop_weight
        ) * adjustment

        zone_slabs = cached_zone_slabs(pickup_zone, vehicle_type)
        zone_pricing_configs = extract_zone_pricing_configs(pickup_zone, drop_zone)

        Result.new(
          base_fare_paise: base_fare.round,
          min_fare_paise: min_fare.round,
          per_km_rate_paise: per_km_rate.round,
          base_distance_m: defaults[:base_distance_m],
          source: :inter_zone_formula,
          pricing_mode: :linear,
          zone_info: {
            pickup_zone: pickup_zone&.zone_code,
            pickup_type: pickup_zone&.zone_type,
            drop_zone: drop_zone&.zone_code,
            drop_type: drop_zone&.zone_type,
            time_band: time_band,
            formula_weights: { origin: pickup_weight, destination: drop_weight },
            adjustment_factor: adjustment
          },
          zone_slabs: zone_slabs,
          fuel_surcharge_pct: zone_pricing_configs[:fuel_surcharge_pct],
          zone_multiplier: 1.0,  # Pre-calculated, no additional multiplier
          special_location_surcharge: zone_pricing_configs[:special_location_surcharge],
          oda_config: zone_pricing_configs[:oda_config]
        )
      end

      # Load inter-zone formula config from city-specific YAML (single source of truth).
      # The YAML uses patterns like "any_to_airport_logistics" which match
      # any origin zone type going to airport_logistics.
      def load_inter_zone_config(city_code)
        city_folder = city_folder_for(city_code)

        # Expire stale cache entry (TTL-based)
        timestamps = self.class.inter_zone_cache_timestamps
        if timestamps[city_folder] && (Time.current - timestamps[city_folder]) > INTER_ZONE_CACHE_TTL
          self.class.inter_zone_config_cache.delete(city_folder)
          timestamps.delete(city_folder)
        end

        self.class.inter_zone_config_cache[city_folder] ||= begin
          config_path = Rails.root.join('config', 'zones', city_folder, 'vehicle_defaults.yml')
          if File.exist?(config_path)
            yaml = YAML.load_file(config_path)
            formula = yaml['inter_zone_formula'] || {}
            type_adjustments = formula['type_adjustments'] || {}

            # Convert YAML patterns to lookup hash.
            lookup = {}
            type_adjustments.each do |pattern_key, time_values|
              next if pattern_key == 'default'
              symbolized = time_values.transform_keys(&:to_sym).transform_values(&:to_f)

              parts = pattern_key.split('_to_')
              next unless parts.length == 2

              from_part = parts[0]
              to_part = parts[1]

              if from_part == 'any'
                lookup[[:any, to_part]] = symbolized
              elsif to_part == 'any'
                lookup[[from_part, :any]] = symbolized
              else
                lookup[[from_part, to_part]] = symbolized
              end
            end

            {
              origin_weight: (formula['origin_weight'] || DEFAULT_ORIGIN_WEIGHT).to_f,
              destination_weight: (formula['destination_weight'] || DEFAULT_DESTINATION_WEIGHT).to_f,
              adjustments: lookup,
              default: (type_adjustments['default'] || {}).transform_keys(&:to_sym).transform_values(&:to_f)
            }
          else
            {}
          end
        rescue StandardError => e
          Rails.logger.warn("Inter-zone config load failed for #{city_code}: #{e.message}")
          {}
        end.tap { self.class.inter_zone_cache_timestamps[city_folder] = Time.current }
      end

      def city_folder_for(city_code)
        normalized = city_code.to_s.downcase
        CITY_FILE_MAPPING[normalized] || normalized
      end

      def get_zone_type_adjustment(from_type, to_type, time_band, inter_zone_config)
        return 1.0 unless time_band.present?

        adjustments = inter_zone_config[:adjustments] || {}
        band = time_band.to_sym

        # Try exact match first
        exact = adjustments[[from_type, to_type]]
        return exact[band] || 1.0 if exact

        # Try wildcard: any → destination
        any_to_dest = adjustments[[:any, to_type]]
        return any_to_dest[band] || 1.0 if any_to_dest

        # Try wildcard: origin → any
        origin_to_any = adjustments[[from_type, :any]]
        return origin_to_any[band] || 1.0 if origin_to_any

        # Default
        default = inter_zone_config[:default] || {}
        default[band] || 1.0
      end
      
      # Extract zone-level pricing configurations (Industry standard patterns)
      # Based on Cogoport/ShipX ODA, FSC, SLS patterns
      def extract_zone_pricing_configs(pickup_zone, drop_zone)
        # Default configs
        configs = {
          fuel_surcharge_pct: 0.0,
          zone_multiplier: 1.0,
          special_location_surcharge: 0,
          oda_config: { pickup_is_oda: false, drop_is_oda: false, both_oda: false, surcharge_pct: 0.0 }
        }
        
        return configs unless pickup_zone || drop_zone
        
        # Use pickup zone as primary for pricing (origin-zone pricing pattern)
        primary_zone = pickup_zone || drop_zone
        
        # FSC: Fuel Surcharge % (from zone config or default 0)
        configs[:fuel_surcharge_pct] = primary_zone.try(:effective_fuel_surcharge_pct) || 0.0
        
        # Zone Multiplier: SLS (Special Location Surcharge)
        configs[:zone_multiplier] = primary_zone.try(:effective_zone_multiplier) || 1.0
        
        # Special Location Surcharge (flat fee for airports, tech parks, etc.)
        configs[:special_location_surcharge] = primary_zone.try(:special_location_surcharge_paise) || 0
        
        # ODA (Out of Delivery Area) - Cogoport pattern
        # If BOTH pickup AND drop are ODA, apply extra surcharge
        pickup_is_oda = pickup_zone.try(:is_oda) || false
        drop_is_oda = drop_zone.try(:is_oda) || false
        both_oda = pickup_is_oda && drop_is_oda
        
        # ODA surcharge % (use pickup zone's config, default 5%)
        oda_pct = both_oda ? (primary_zone.try(:effective_oda_surcharge_pct) || 5.0) : 0.0
        
        configs[:oda_config] = {
          pickup_is_oda: pickup_is_oda,
          drop_is_oda: drop_is_oda,
          both_oda: both_oda,
          surcharge_pct: oda_pct
        }
        
        configs
      end
      
      # Fetch zone-specific distance slabs
      def fetch_zone_slabs(zone, vehicle_type)
        return nil unless zone && defined?(ZoneDistanceSlab)
        
        slabs = ZoneDistanceSlab.for_zone_vehicle(zone.id, vehicle_type)
        return nil if slabs.empty?
        
        slabs.map do |s|
          {
            min_distance_m: s.min_distance_m,
            max_distance_m: s.max_distance_m,
            per_km_rate_paise: s.per_km_rate_paise,
            flat_fare_paise: s.flat_fare_paise
          }
        end
      rescue StandardError => e
        Rails.logger.warn("Zone slabs lookup failed: #{e.message}")
        nil
      end

      def find_zone(city_code, lat, lng)
        # Load zones once per city per resolver instance (avoids N+1 in multi-quote)
        @zones_cache ||= {}
        @zones_cache[city_code] ||= Zone.for_city(city_code).active
          .order(priority: :desc, zone_code: :asc).to_a

        @zones_cache[city_code].each do |z|
          return z if z.contains_point?(lat, lng)
        end
        nil
      end

      # =========================================================================
      # INSTANCE-LEVEL CACHING (avoids N+1 in multi-quote)
      # Each cache loads ALL records for a city/zone once, then filters in Ruby.
      # =========================================================================

      # Cache all active PricingConfigs for a city, filter by vehicle_type in Ruby
      def cached_city_config(city_code, vehicle_type)
        @city_configs_cache ||= {}
        @city_configs_cache[city_code] ||= PricingConfig
          .where(city_code: city_code.to_s.downcase, active: true)
          .to_a
        @city_configs_cache[city_code].find { |c| c.vehicle_type == vehicle_type }
      end

      # Cache all active ZonePairVehiclePricings for a zone pair, filter in Ruby
      # Replicates ZonePairVehiclePricing.find_override priority logic without DB queries
      def cached_pair_pricing(city_code, from_zone_id, to_zone_id, vehicle_type, time_band)
        @pair_pricings_cache ||= {}
        key = "#{city_code}:#{from_zone_id}:#{to_zone_id}"
        @pair_pricings_cache[key] ||= ZonePairVehiclePricing
          .where(city_code: city_code.to_s.downcase, active: true)
          .where(
            "(from_zone_id = :from AND to_zone_id = :to) OR " \
            "(from_zone_id = :to AND to_zone_id = :from AND directional = false)",
            from: from_zone_id, to: to_zone_id
          )
          .to_a

        pairs = @pair_pricings_cache[key]

        # 1. Exact match with time_band
        result = pairs.find { |p| p.vehicle_type == vehicle_type && p.time_band == time_band &&
                                   p.from_zone_id == from_zone_id && p.to_zone_id == to_zone_id }
        return result if result

        # 2. Without time_band (fallback)
        if time_band.present?
          result = pairs.find { |p| p.vehicle_type == vehicle_type && p.time_band.nil? &&
                                     p.from_zone_id == from_zone_id && p.to_zone_id == to_zone_id }
          return result if result
        end

        # 3. Non-directional swapped with time_band
        result = pairs.find { |p| p.vehicle_type == vehicle_type && p.time_band == time_band &&
                                   p.from_zone_id == to_zone_id && p.to_zone_id == from_zone_id && !p.directional }
        return result if result

        # 4. Non-directional swapped without time_band
        if time_band.present?
          pairs.find { |p| p.vehicle_type == vehicle_type && p.time_band.nil? &&
                            p.from_zone_id == to_zone_id && p.to_zone_id == from_zone_id && !p.directional }
        end
      end

      # Cache all active ZoneVehiclePricings for a zone (with eager-loaded time_pricings)
      def cached_zone_pricing(city_code, zone, vehicle_type)
        return nil unless zone
        @zone_pricings_cache ||= {}
        key = "#{city_code}:#{zone.id}"
        @zone_pricings_cache[key] ||= ZoneVehiclePricing
          .where(city_code: city_code.to_s.downcase, zone: zone, active: true)
          .includes(:time_pricings)
          .to_a
        @zone_pricings_cache[key].find { |zp| zp.vehicle_type == vehicle_type }
      end

      # Cache all zone distance slabs for a zone, filter by vehicle_type in Ruby
      def cached_zone_slabs(zone, vehicle_type)
        return nil unless zone && defined?(ZoneDistanceSlab)
        @zone_slabs_cache ||= {}
        @zone_slabs_cache[zone.id] ||= ZoneDistanceSlab
          .where(zone_id: zone.id, active: true)
          .order(:min_distance_m)
          .to_a

        slabs = @zone_slabs_cache[zone.id].select { |s| s.vehicle_type == vehicle_type }
        return nil if slabs.empty?

        slabs.map do |s|
          {
            min_distance_m: s.min_distance_m,
            max_distance_m: s.max_distance_m,
            per_km_rate_paise: s.per_km_rate_paise,
            flat_fare_paise: s.flat_fare_paise
          }
        end
      rescue StandardError => e
        Rails.logger.warn("Zone slabs lookup failed: #{e.message}")
        nil
      end
    end
  end
end
