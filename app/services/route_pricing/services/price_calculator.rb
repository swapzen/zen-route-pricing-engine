# frozen_string_literal: true

module RoutePricing
  module Services
    class PriceCalculator
      # Traffic multiplier curve parameters
      TRAFFIC_CURVE_EXPONENT = 0.8
      TRAFFIC_MAX_MULTIPLIER = 1.2  # Cap at +20% for traffic (was 1.5 for pilot)
      
      # Unit economics guardrail
      MIN_TARGET_MARGIN_PCT = 5.0  # Minimum 5% margin required
      
      # =====================================================================
      # INDUSTRY-STANDARD PRICING COMPONENTS (Cogoport/ShipX patterns)
      # =====================================================================
      # FSC: Fuel Surcharge - applied as % of base fare (industry: 5-15%)
      FUEL_SURCHARGE_PCT = 0.0  # Set to 0 during Porter calibration, enable later
      
      # SLS: Special Location Surcharge multipliers by zone type
      # Maps zone_type to pricing premium multiplier
      ZONE_TYPE_MULTIPLIERS = {
        'tech_corridor'      => 1.00,  # Competitive for tech areas
        'business_cbd'       => 1.05,  # Premium for CBD (congestion premium)
        'airport_logistics'  => 1.10,  # Long-haul premium
        'residential_growth' => 0.95,  # Discount for adoption
        'industrial'         => 0.95,  # Volume discount
        'outer_ring'         => 1.00,  # Neutral for outer areas
        'default'            => 1.00
      }.freeze
      
      # ODA: Out of Delivery Area logic (Cogoport pattern)
      # If BOTH pickup AND drop are in outer/industrial zones, apply surcharge
      ODA_DOUBLE_ZONE_TYPES = %w[outer_ring industrial airport_logistics].freeze
      ODA_SURCHARGE_MULTIPLIER = 1.05  # 5% surcharge for both-ODA routes

      def initialize(config:)
        @config = config
      end

      def calculate(distance_m:, pickup_lat: nil, pickup_lng: nil, drop_lat: nil, drop_lng: nil,
                    item_value_paise: nil, duration_in_traffic_s: nil, duration_s: nil, quote_time: Time.current)
        
        # Step 0: Determine time band
        hour = quote_time.hour
        time_band = case hour
                    when 6...12 then 'morning'
                    when 12...18 then 'afternoon'
                    else 'evening'
                    end
        
        # Step 1: Resolve Zone Pricing (v5.0 Time-Aware Zone-Based Structure)
        zone_pricing = ZonePricingResolver.new.resolve(
          city_code: @config.city_code,
          vehicle_type: @config.vehicle_type,
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          time_band: time_band
        )

        Rails.logger.info("Pricing Source: #{zone_pricing.source} | Zone Info: #{zone_pricing.zone_info}")

        # Step 1: Base fare (from resolved pricing)
        base_fare = [zone_pricing.base_fare_paise, zone_pricing.min_fare_paise].max

        # Step 2: Chargeable distance
        # Use resolved base_distance (defaults to config if not overridden)
        base_distance = zone_pricing.base_distance_m || @config.base_distance_m
        chargeable_m = [0, distance_m - base_distance].max

        # Step 3: Distance component
        # Strategy: Use pricing mode from resolver (:slab for city default, :zone_slab, :linear for overlays)
        distance_component = case zone_pricing.pricing_mode
        when :zone_slab
          # Use zone-specific slabs (highest priority)
          calculate_zone_slab_cost(zone_pricing.zone_slabs, chargeable_m) || 
            calculate_linear_cost(chargeable_m, zone_pricing.per_km_rate_paise)
        when :slab
          # Use city-level slabs
          calculate_distance_component(chargeable_m)
        else
          # Linear pricing for overrides
          calculate_linear_cost(chargeable_m, zone_pricing.per_km_rate_paise)
        end

        # Step 4: Raw subtotal
        raw_subtotal = base_fare + distance_component.to_i

        # Step 4b: Distance Band Shaping (Option B)
        # Apply multipliers to shape the curve for Micro/Short/Medium/Long trips
        band_multiplier = calculate_distance_band_multiplier(@config.vehicle_type, distance_m)
        raw_subtotal = (raw_subtotal * band_multiplier).round
        
        # =====================================================================
        # INDUSTRY-STANDARD CHARGE COMPONENTS (Cogoport/ShipX patterns)
        # Now using CONFIGURABLE zone-level settings instead of hardcoded values
        # =====================================================================
        
        # 4c. Fuel Surcharge (FSC) - From zone config (industry: 8-12%, default 0)
        # Use zone-level FSC if configured, otherwise use global default
        fsc_pct = zone_pricing.fuel_surcharge_pct || FUEL_SURCHARGE_PCT
        fuel_surcharge_paise = (raw_subtotal * fsc_pct).round
        
        # 4d. Zone Type Multiplier (SLS - Special Location Surcharge)
        # From zone config (configurable per zone instead of hardcoded by type)
        zone_type_mult = zone_pricing.zone_multiplier || calculate_zone_type_multiplier(zone_pricing.zone_info)
        
        # 4e. ODA Surcharge (Out of Delivery Area - Cogoport pattern)
        # From zone config (both_oda triggers surcharge_pct)
        oda_mult = calculate_oda_multiplier_from_config(zone_pricing.oda_config)
        
        # 4f. Special Location Surcharge (flat fee for airports, tech parks)
        # From zone config (paise amount)
        special_location_surcharge = zone_pricing.special_location_surcharge || 0
        
        # Apply industry-standard components
        raw_subtotal = (raw_subtotal * zone_type_mult * oda_mult).round
        raw_subtotal += fuel_surcharge_paise
        raw_subtotal += special_location_surcharge


        # =====================================================================
        # 3-LAYER DYNAMIC SURGE CALCULATION
        # =====================================================================
        # Check if we're in calibration mode (for tuning against market benchmarks)
        calibration_mode = ENV['PRICING_MODE'] == 'calibration'
        
        # v5.0: Routes with time-aware zone pricing bypass all multipliers
        # Time-specific base prices already encode time-of-day demand
        time_aware_bypass = [:zone_time_override, :corridor_override].include?(zone_pricing.source)

        # =====================================================================

        # =====================================================================
        # DYNAMIC FACTOR CALCULATION
        # =====================================================================
        if calibration_mode || time_aware_bypass
          # -----------------------------------------------------------
          # PURE CALIBRATION MODE or TIME-AWARE ZONE PRICING
          # -----------------------------------------------------------
          # We want to tune the BASE SLABS against Porter's base.
          # Porter's price includes their zone/demand logic, but our 
          # baseline shouldn't chase their surges.
          # -----------------------------------------------------------
          traffic_multiplier = 1.0
          time_multiplier    = 1.0
          zone_multiplier    = 1.0
          combined_surge     = 1.0
          
          variance_buffer    = 0.0
          high_value_buffer  = 0.0
          margin_total       = 0.0
        else
          # -----------------------------------------------------------
          # PRODUCTION MODE: Full Dynamics
          # -----------------------------------------------------------
          
          # 1. Traffic Multiplier
          traffic_multiplier = calculate_traffic_multiplier(
            duration_in_traffic_s, 
            duration_s
          )

          # 2. Time of Day + Distance-Aware Multiplier (v3.0)
          distance_km = distance_m / 1000.0
          time_multiplier = @config.calculate_surge_multiplier(
            time: quote_time,
            distance_km: distance_km,
            vehicle_type: @config.vehicle_type,
            traffic_ratio: nil  # Already handled by Layer 1, don't double-count!
          )

          # 3. Zone Multiplier
          zone_multiplier = calculate_zone_multiplier(
            pickup_lat, 
            pickup_lng,
            drop_lat,
            drop_lng
          )

          # 4. Combined Surge (capped at 2.0 for safety)
          combined_surge = [traffic_multiplier * time_multiplier * zone_multiplier, 2.0].min

          # Buffers & Margins
          variance_buffer = @config.variance_buffer_pct || 0.0
          high_value_buffer = 0.0
          
          # Margin from config (pilot: 0.0, rely on guardrail)
          margin_total = @config.min_margin_pct || 0.0
        end

        # Apply Multipliers
        multiplied = raw_subtotal * combined_surge * @config.vehicle_multiplier * @config.city_multiplier
        
        # Apply Buffers
        subtotal_with_buffers = multiplied * (1 + variance_buffer + high_value_buffer)
        
        # Apply Margin
        price_after_margin = subtotal_with_buffers * (1 + margin_total)

        # Rounding
        if calibration_mode
          # Precise rounding for calibration
          final_price_paise = price_after_margin.round.to_i
        else
          # Market-friendly rounding (nearest ₹10)
          final_price_paise = (((price_after_margin + 999) / 1000) * 1000).to_i
        end

        # Price floor
        final_price_paise = [final_price_paise, @config.min_fare_paise.to_i].max

        # =====================================================================
        # UNIT ECONOMICS (Internal - Not shown to user)
        # =====================================================================
        # Use raw_subtotal as proxy for vendor cost (calibrated to Porter)
        estimated_vendor_cost_paise = raw_subtotal
        
        # Payment gateway fee (~2% of final price)
        pg_fee_paise = (final_price_paise * 0.02).round
        
        # Operational buffer (₹2 per order for support/misc)
        support_buffer_paise = 200
        
        # Google Maps API cost (trivial, ~10 paise)
        maps_cost_paise = 10
        
        # Total variable cost per order
        total_cost_paise = estimated_vendor_cost_paise + pg_fee_paise + support_buffer_paise + maps_cost_paise
        
        # Contribution margin
        margin_paise = final_price_paise - total_cost_paise
        margin_pct = total_cost_paise > 0 ? ((margin_paise.to_f / total_cost_paise) * 100).round(1) : 0.0
        
        # =====================================================================
        # UNIT ECONOMICS GUARDRAIL (Never lose money on a trip)
        # =====================================================================
        if margin_pct < MIN_TARGET_MARGIN_PCT
          # Bump price to achieve minimum margin
          required_price_paise = (total_cost_paise * (1 + MIN_TARGET_MARGIN_PCT / 100.0)).ceil
          
          # Round up to nearest ₹10 for clean pricing
          guardrail_price_paise = (((required_price_paise + 999) / 1000) * 1000).to_i
          
          # Log the adjustment
          Rails.logger.warn(
            "[UNIT_ECON_GUARDRAIL] Price bumped: " \
            "#{final_price_paise/100.0} → #{guardrail_price_paise/100.0} " \
            "(margin was #{margin_pct}%, needed #{MIN_TARGET_MARGIN_PCT}%)"
          )
          
          # Apply guardrail
          final_price_paise = guardrail_price_paise.to_i
          
          # Recalculate with new price
          pg_fee_paise = (final_price_paise * 0.02).round
          total_cost_paise = estimated_vendor_cost_paise + pg_fee_paise + support_buffer_paise + maps_cost_paise
          margin_paise = final_price_paise - total_cost_paise
          margin_pct = total_cost_paise > 0 ? ((margin_paise.to_f / total_cost_paise) * 100).round(1) : 0.0
        end
        # =====================================================================
        
        unit_economics = {
          estimated_vendor_cost_paise: estimated_vendor_cost_paise,
          pg_fee_paise: pg_fee_paise,
          support_buffer_paise: support_buffer_paise,
          maps_cost_paise: maps_cost_paise,
          total_cost_paise: total_cost_paise,
          margin_paise: margin_paise,
          margin_pct: margin_pct,
          profitable: margin_paise >= 0,
          guardrail_applied: margin_pct >= MIN_TARGET_MARGIN_PCT
        }
        
        # =====================================================================

        # Build detailed breakdown
        breakdown = {
          calibration_mode: calibration_mode,
          base_fare: base_fare,
          chargeable_distance_m: chargeable_m,
          distance_component: distance_component,
          slab_pricing_used: @config.pricing_distance_slabs.any?,
          # Industry-standard components (Cogoport/ShipX)
          fuel_surcharge_pct: fsc_pct,
          fuel_surcharge_paise: fuel_surcharge_paise,
          zone_type_multiplier: zone_type_mult.round(3),
          oda_multiplier: oda_mult.round(3),
          special_location_surcharge_paise: special_location_surcharge,
          raw_subtotal: raw_subtotal,
          # 3-layer surge breakdown
          traffic_multiplier: traffic_multiplier.round(3),
          time_multiplier: time_multiplier.round(3),
          zone_multiplier: zone_multiplier.round(3),
          combined_surge: combined_surge.round(3),
          # Traffic details
          traffic_ratio: (duration_in_traffic_s && duration_s && duration_s > 0) ? 
                         (duration_in_traffic_s.to_f / duration_s).round(2) : nil,
          duration_s: duration_s,
          duration_in_traffic_s: duration_in_traffic_s,
          # Other multipliers
          vehicle_multiplier: @config.vehicle_multiplier.to_f,
          city_multiplier: @config.city_multiplier.to_f,
          after_multipliers: multiplied,
          variance_buffer: variance_buffer,
          high_value_buffer: high_value_buffer,
          subtotal_with_buffers: subtotal_with_buffers,
          margin_guardrail: margin_total,
          price_after_margin: price_after_margin,
          final_price: final_price_paise,
          # Unit economics (internal monitoring)
          unit_economics: unit_economics
        }.freeze

        {
          final_price_paise: final_price_paise,
          breakdown: breakdown
        }
      end

      private

      # Layer 2: DELETED - Replaced by PricingConfig#calculate_surge_multiplier in v3.0
      # Old calculate_time_multiplier method removed - now handled by PricingConfig

      # Layer 1: Real-time traffic multiplier using smooth curve
      def calculate_traffic_multiplier(duration_in_traffic_s, duration_s)
        return 1.0 if duration_in_traffic_s.nil? || duration_s.nil? || duration_s <= 0

        traffic_ratio = duration_in_traffic_s.to_f / duration_s

        # Sanity check
        return 1.0 if traffic_ratio < 0.9 || traffic_ratio > 3.0

        # Smooth curve: y = 1 + 0.5 * (x - 1)^0.8, capped at 1.5
        return 1.0 if traffic_ratio <= 1.0

        base = (traffic_ratio - 1.0) ** TRAFFIC_CURVE_EXPONENT
        [1.0 + (0.5 * base), TRAFFIC_MAX_MULTIPLIER].min
      end

      # Layer 3: Zone demand multiplier (v4.0: vehicle-category aware)
      def calculate_zone_multiplier(pickup_lat, pickup_lng, drop_lat = nil, drop_lng = nil)
        return 1.0 unless pickup_lat && pickup_lng

        # Check if PricingZoneMultiplier model exists
        return 1.0 unless defined?(PricingZoneMultiplier)

        # v4.0: Pass vehicle_type for category-specific multipliers
        PricingZoneMultiplier.route_multiplier(
          city_code: @config.city_code,
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          vehicle_type: @config.vehicle_type
        )
      rescue => e
        Rails.logger.warn("Zone multiplier lookup failed: #{e.message}")
        1.0
      end

      # Linear pricing calculation
      def calculate_linear_cost(chargeable_m, per_km_rate_paise)
        km_to_charge = chargeable_m / 1000.0
        (km_to_charge * per_km_rate_paise).round
      end
      
      # Zone-specific slab calculation
      def calculate_zone_slab_cost(zone_slabs, distance_m)
        return nil if zone_slabs.blank?
        
        total_paise = 0
        remaining_m = distance_m
        
        zone_slabs.each do |slab|
          break if remaining_m <= 0
          
          slab_start_m = slab[:min_distance_m]
          slab_end_m = slab[:max_distance_m] || Float::INFINITY
          
          meters_in_slab = if distance_m <= slab_start_m
                             0
                           elsif distance_m >= slab_end_m
                             slab_end_m - slab_start_m
                           else
                             distance_m - slab_start_m
                           end
          
          meters_to_charge = [meters_in_slab, remaining_m].min
          
          if meters_to_charge > 0
            # Use flat fare if defined for first slab, otherwise per-km rate
            if slab[:flat_fare_paise] && slab_start_m == 0
              total_paise += slab[:flat_fare_paise]
            else
              km_to_charge = meters_to_charge / 1000.0
              total_paise += (km_to_charge * slab[:per_km_rate_paise]).round
            end
            remaining_m -= meters_to_charge
          end
        end
        
        total_paise
      end
      
      # Distance component using city slabs
      def calculate_distance_component(chargeable_m)
        slabs = @config.pricing_distance_slabs.ordered
        
        if slabs.any?
          calculate_slab_cost(slabs, chargeable_m)
        else
          chargeable_km = (chargeable_m + 999) / 1000
          chargeable_km * @config.per_km_rate_paise
        end
      end

      def calculate_slab_cost(slabs, distance_m)
        return 0 if distance_m <= 0

        total_paise = 0
        remaining_m = distance_m

        slabs.each do |slab|
          break if remaining_m <= 0

          slab_start_m = slab.min_distance_m
          slab_end_m = slab.max_distance_m || Float::INFINITY

          meters_in_slab = if distance_m <= slab_start_m
                             0
                           elsif distance_m >= slab_end_m
                             slab_end_m - slab_start_m
                           else
                             distance_m - slab_start_m
                           end

          meters_to_charge = [meters_in_slab, remaining_m].min
          
          if meters_to_charge > 0
            km_to_charge = meters_to_charge / 1000.0
            total_paise += (km_to_charge * slab.per_km_rate_paise).round
            remaining_m -= meters_to_charge
          end
        end

        total_paise
      end

      # Distance Band Shaping Logic
      SMALL_VEHICLES = %w[two_wheeler scooter].freeze
      MID_TRUCKS     = %w[mini_3w three_wheeler three_wheeler_ev tata_ace pickup_8ft eeco].freeze
      HEAVY_TRUCKS   = %w[tata_407 canter_14ft].freeze

      def calculate_distance_band_multiplier(vehicle_type, distance_m)
        # Distance band multipliers for shaping the price curve
        # Tuned based on Porter benchmark analysis:
        # - Micro trips: Cheaper (high competition, customer price sensitivity)
        # - Short trips: Baseline (well-calibrated global rates)
        # - Medium trips: Slight premium (less competition, operational costs)
        # - Long trips: Neutral (volume discount balances distance premium)
        distance_km = distance_m / 1000.0
        
        band = case distance_km
               when 0...5   then :micro
               when 5...12  then :short
               when 12...20 then :medium
               else              :long
               end

        # Tuned multipliers for Porter alignment (v6.1 calibration)
        if SMALL_VEHICLES.include?(vehicle_type)
          # Small vehicles: Aggressive micro discount (high competition segment)
          { micro: 0.85, short: 1.00, medium: 1.05, long: 1.00 }[band]
        elsif MID_TRUCKS.include?(vehicle_type)
          # Mid trucks: Moderate micro discount (operational efficiency at short range)
          { micro: 0.90, short: 1.00, medium: 1.05, long: 1.00 }[band]
        else # HEAVY_TRUCKS
          # Heavy trucks: Minimal micro discount (fixed costs dominate)
          { micro: 0.95, short: 1.00, medium: 1.05, long: 1.00 }[band]
        end || 1.0
      end
      
      # =====================================================================
      # INDUSTRY-STANDARD PRICING METHODS (Cogoport/ShipX patterns)
      # =====================================================================
      
      # Zone Type Multiplier (SLS - Special Location Surcharge)
      # Different zone types have different cost structures:
      # - CBD: Higher congestion, parking costs → premium
      # - Tech Corridor: Competitive market → neutral
      # - Outer Ring: Lower demand → can be neutral or discounted
      # - Industrial: Volume play → slight discount
      def calculate_zone_type_multiplier(zone_info)
        return 1.0 unless zone_info
        
        pickup_type = zone_info[:pickup_type]
        drop_type = zone_info[:drop_type]
        
        # Use pickup zone type as primary (origin-zone pricing pattern)
        zone_type = pickup_type || drop_type || 'default'
        
        ZONE_TYPE_MULTIPLIERS[zone_type] || ZONE_TYPE_MULTIPLIERS['default']
      end
      
      # ODA Multiplier (Out of Delivery Area - Cogoport pattern)
      # If BOTH origin AND destination are in outer/remote zones,
      # apply surcharge because:
      # 1. Driver has to travel from/to remote area (deadhead)
      # 2. Less chance of backhaul/return load
      # Industry standard: 1.5x-2x for ODA, we use 1.05x (5% surcharge)
      def calculate_oda_multiplier(zone_info)
        return 1.0 unless zone_info
        
        pickup_type = zone_info[:pickup_type]
        drop_type = zone_info[:drop_type]
        
        pickup_is_oda = ODA_DOUBLE_ZONE_TYPES.include?(pickup_type)
        drop_is_oda = ODA_DOUBLE_ZONE_TYPES.include?(drop_type)
        
        # Only apply if BOTH are ODA (Cogoport pattern)
        if pickup_is_oda && drop_is_oda
          ODA_SURCHARGE_MULTIPLIER
        else
          1.0
        end
      end
      
      # ODA Multiplier using zone-level config (preferred over hardcoded)
      # Uses is_oda flag and oda_surcharge_pct from Zone model
      def calculate_oda_multiplier_from_config(oda_config)
        return 1.0 unless oda_config && oda_config[:both_oda]
        
        # Convert percentage to multiplier (e.g., 5% → 1.05)
        surcharge_pct = oda_config[:surcharge_pct] || 5.0
        1.0 + (surcharge_pct / 100.0)
      end
    end
  end
end
