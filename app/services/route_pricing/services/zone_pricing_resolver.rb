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
      ORIGIN_WEIGHT = 0.6
      DESTINATION_WEIGHT = 0.4

      def resolve(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, time_band: nil)
        # 1. Resolve Zones
        pickup_zone = find_zone(city_code, pickup_lat, pickup_lng)
        drop_zone = find_zone(city_code, drop_lat, drop_lng)
        
        # 2. Global Default Config (Fallback)
        global_config = PricingConfig.find_by(city_code: city_code, vehicle_type: vehicle_type, active: true)
        
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
          pair_pricing = ZonePairVehiclePricing.find_override(
            city_code, 
            pickup_zone.id, 
            drop_zone.id, 
            vehicle_type,
            time_band: time_band
          )
          if pair_pricing
             # Corridor pricing uses linear mode with explicit rates
             # Zone multipliers are bypassed (corridor rates are fully calibrated)
             zone_slabs = fetch_zone_slabs(pickup_zone, vehicle_type)
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
            pickup_zone, drop_zone, vehicle_type, time_band, defaults
          )
          return inter_zone_result if inter_zone_result
        end

        # 5. Check Zone-Specific Override (with Time Awareness) - INTRA-ZONE pricing
        reference_zone = pickup_zone
        
        if reference_zone
          zone_pricing = ZoneVehiclePricing.where('LOWER(city_code) = LOWER(?)', city_code)
            .where(zone: reference_zone, vehicle_type: vehicle_type, active: true)
            .first

          if zone_pricing
            # Fetch zone-specific slabs
            zone_slabs = fetch_zone_slabs(reference_zone, vehicle_type)
            
            # 5a. Try time-specific pricing first
            if time_band.present?
              time_pricing = zone_pricing.time_pricings.active.find_by(time_band: time_band)
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
        zone_slabs = pickup_zone ? fetch_zone_slabs(pickup_zone, vehicle_type) : nil
        Result.new(defaults.merge(zone_slabs: zone_slabs))
      end

      private

      # =========================================================================
      # INTER-ZONE FORMULA
      # =========================================================================
      # Calculates pricing for zone pairs without explicit corridors
      # Uses weighted average of origin and destination zone rates
      # with adjustments based on zone type combinations
      def calculate_inter_zone_pricing(pickup_zone, drop_zone, vehicle_type, time_band, defaults)
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
        adjustment = get_zone_type_adjustment(pickup_zone.zone_type, drop_zone.zone_type, time_band)

        # Build result with weighted average
        build_inter_zone_result(pickup_pricing, drop_pricing, ORIGIN_WEIGHT, DESTINATION_WEIGHT,
                               pickup_zone, drop_zone, vehicle_type, defaults, time_band, adjustment)
      end

      def get_zone_time_pricing(zone, vehicle_type, time_band)
        return nil unless zone

        zone_pricing = ZoneVehiclePricing.where('LOWER(city_code) = LOWER(?)', zone.city)
          .where(zone: zone, vehicle_type: vehicle_type, active: true)
          .first

        return nil unless zone_pricing

        if time_band.present?
          time_pricing = zone_pricing.time_pricings.active.find_by(time_band: time_band)
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

        zone_slabs = fetch_zone_slabs(pickup_zone, vehicle_type)
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

      # Zone type adjustments based on commute patterns
      ZONE_TYPE_ADJUSTMENTS = {
        # Morning rush: residential → tech (higher demand)
        ['residential_dense', 'tech_corridor'] => { morning: 1.08, afternoon: 1.0, evening: 0.95 },
        ['residential_mixed', 'tech_corridor'] => { morning: 1.05, afternoon: 1.0, evening: 0.95 },
        ['residential_growth', 'tech_corridor'] => { morning: 1.05, afternoon: 1.0, evening: 0.95 },
        
        # Evening rush: tech → residential (reverse commute)
        ['tech_corridor', 'residential_dense'] => { morning: 0.95, afternoon: 1.0, evening: 1.08 },
        ['tech_corridor', 'residential_mixed'] => { morning: 0.95, afternoon: 1.0, evening: 1.05 },
        ['tech_corridor', 'residential_growth'] => { morning: 0.95, afternoon: 1.0, evening: 1.05 },
        
        # Old city congestion premium
        ['residential_dense', 'traditional_commercial'] => { morning: 1.05, afternoon: 1.08, evening: 1.05 },
        ['residential_mixed', 'traditional_commercial'] => { morning: 1.05, afternoon: 1.08, evening: 1.05 },
        ['tech_corridor', 'traditional_commercial'] => { morning: 1.05, afternoon: 1.08, evening: 1.05 },
        ['business_cbd', 'traditional_commercial'] => { morning: 1.05, afternoon: 1.08, evening: 1.05 },
        
        # Airport premium
        ['airport_logistics', 'tech_corridor'] => { morning: 1.10, afternoon: 1.05, evening: 1.10 },
        ['airport_logistics', 'business_cbd'] => { morning: 1.10, afternoon: 1.05, evening: 1.10 },
        ['airport_logistics', 'premium_residential'] => { morning: 1.15, afternoon: 1.10, evening: 1.15 },
        ['tech_corridor', 'airport_logistics'] => { morning: 1.10, afternoon: 1.05, evening: 1.10 },
        ['business_cbd', 'airport_logistics'] => { morning: 1.10, afternoon: 1.05, evening: 1.10 },
        ['premium_residential', 'airport_logistics'] => { morning: 1.15, afternoon: 1.10, evening: 1.15 },
        
        # Premium residential premium
        ['premium_residential', 'tech_corridor'] => { morning: 1.10, afternoon: 1.05, evening: 1.05 },
        ['premium_residential', 'business_cbd'] => { morning: 1.08, afternoon: 1.05, evening: 1.05 },
        ['tech_corridor', 'premium_residential'] => { morning: 1.05, afternoon: 1.05, evening: 1.10 },
        ['business_cbd', 'premium_residential'] => { morning: 1.05, afternoon: 1.05, evening: 1.08 },
        
        # Industrial routes (volume discount potential)
        ['industrial', 'tech_corridor'] => { morning: 0.98, afternoon: 0.98, evening: 0.98 },
        ['industrial', 'business_cbd'] => { morning: 0.98, afternoon: 0.98, evening: 0.98 },
        ['tech_corridor', 'industrial'] => { morning: 0.98, afternoon: 0.98, evening: 0.98 },
        ['business_cbd', 'industrial'] => { morning: 0.98, afternoon: 0.98, evening: 0.98 }
      }.freeze

      def get_zone_type_adjustment(from_type, to_type, time_band)
        key = [from_type, to_type]
        adjustments = ZONE_TYPE_ADJUSTMENTS[key]
        
        return 1.0 unless adjustments && time_band.present?
        
        adjustments[time_band.to_sym] || 1.0
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
        # Optimized lookup would use PostGIS/CockroachDB spatial index.
        # For now, looping through active zones in memory (efficient for <100 zones).
        # Sorted by priority so higer priority zones (e.g. specific tech parks) match first.
        Zone.for_city(city_code).active.order(priority: :desc).each do |z|
          return z if z.contains_point?(lat, lng)
        end
        nil
      end
    end
  end
end
