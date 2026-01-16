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
          base_fare_paise: global_config&.base_fare_paise || 0,
          min_fare_paise: global_config&.min_fare_paise || 0,
          per_km_rate_paise: global_config&.per_km_rate_paise || 0,
          base_distance_m: global_config&.base_distance_m || 0,
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

        # 4. Check Zone-Specific Override (with Time Awareness)
        reference_zone = pickup_zone
        
        if reference_zone
          # Note: city_code is case-insensitive
          zone_pricing = ZoneVehiclePricing.where('LOWER(city_code) = LOWER(?)', city_code)
            .where(zone: reference_zone, vehicle_type: vehicle_type, active: true)
            .first

          if zone_pricing
            # Fetch zone-specific slabs
            zone_slabs = fetch_zone_slabs(reference_zone, vehicle_type)
            
            # 4a. Try time-specific pricing first
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
            
            # 4b. Fallback to base zone pricing (time-neutral)
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

        # 5. Return Default (with zone slabs if available)
        zone_slabs = pickup_zone ? fetch_zone_slabs(pickup_zone, vehicle_type) : nil
        Result.new(defaults.merge(zone_slabs: zone_slabs))
      end

      private
      
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
