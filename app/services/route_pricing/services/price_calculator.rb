# frozen_string_literal: true

module RoutePricing
  module Services
    class PriceCalculator
      # Traffic multiplier curve parameters
      TRAFFIC_CURVE_EXPONENT = 0.8
      TRAFFIC_MAX_MULTIPLIER = 1.5  # Cap at +50% for traffic
      
      # Unit economics guardrail
      MIN_TARGET_MARGIN_PCT = 12.0  # Minimum 12% margin (covers PG 2% + GST 0.4% + support ₹3 + insurance ₹3 + bad debt 2% + ops 3%)

      # Multiplicative cap: total product of all stacking multipliers cannot exceed this
      MAX_TOTAL_MULTIPLICATIVE_EFFECT = 2.5
      
      # =====================================================================
      # INDUSTRY-STANDARD PRICING COMPONENTS (Cogoport/ShipX patterns)
      # =====================================================================
      # FSC: Fuel Surcharge - applied as % of base fare (industry: 5-15%)
      FUEL_SURCHARGE_PCT = 0.0  # Set to 0 during benchmark calibration, enable later
      
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

      def initialize(config:, zone_resolver: nil, include_inactive: false)
        @config = config
        @zone_resolver = zone_resolver || ZonePricingResolver.new(include_inactive: include_inactive)
      end

      def calculate(distance_m:, pickup_lat: nil, pickup_lng: nil, drop_lat: nil, drop_lng: nil,
                    item_value_paise: nil, duration_in_traffic_s: nil, duration_s: nil, quote_time: Time.current,
                    weight_kg: nil, route_segments: nil, estimated_loading_min: nil, additional_stops: nil)
        
        # Step 0: Determine time band (using city timezone for consistency)
        # IMPORTANT: Convert to city timezone to avoid UTC vs local time mismatch.
        # Without this, a request at 14:00 UTC (19:30 IST) would get 'afternoon'
        # for zone pricing but 'evening' for surge — causing pricing inconsistency.
        local_time = quote_time.in_time_zone(@config.timezone)
        time_band = RoutePricing::Services::TimeBandResolver.resolve(local_time)
        
        # Step 1: Resolve Zone Pricing (v5.0 Time-Aware Zone-Based Structure)
        zone_pricing = @zone_resolver.resolve(
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
        base_fare = zone_pricing.base_fare_paise.to_i

        # Step 2: Chargeable distance
        # Use resolved base_distance (defaults to config if not overridden)
        base_distance = zone_pricing.base_distance_m || @config.base_distance_m
        chargeable_m = [0, distance_m - base_distance].max

        # Step 3: Distance component
        # Phase 1: Route-segment pricing (flag-gated) — uses per-zone rates for each segment
        segment_pricing_used = false
        distance_component = if route_segments.present? && PricingRolloutFlag.enabled?('route_segment_pricing', city_code: @config.city_code)
          segment_pricing_used = true
          calculate_segment_distance_component(route_segments, time_band)
        else
          # Strategy: Use pricing mode from resolver (:slab for city default, :zone_slab, :linear for overlays)
          case zone_pricing.pricing_mode
          when :zone_slab
            calculate_zone_slab_cost(zone_pricing.zone_slabs, chargeable_m) ||
              calculate_linear_cost(chargeable_m, zone_pricing.per_km_rate_paise)
          when :slab
            calculate_distance_component(chargeable_m)
          else
            calculate_linear_cost(chargeable_m, zone_pricing.per_km_rate_paise)
          end
        end

        # Step 3b: Time component (per-minute pricing)
        per_min_rate = zone_pricing.per_min_rate_paise || 0
        time_component = if per_min_rate > 0 && duration_in_traffic_s.present? && duration_in_traffic_s > 0
                           (duration_in_traffic_s / 60.0) * per_min_rate
                         else
                           0
                         end

        # Step 3c: Dead-km charge (pickup distance cost)
        dead_km_charge = calculate_dead_km_charge(pickup_lat, pickup_lng, @config.city_code, time_band)

        # Step 3d: Waiting/loading charge (Phase 5)
        waiting_charge = calculate_waiting_charge(zone_pricing.zone_info)

        # Step 3e: Explicit loading time charge (goods delivery: loading time at pickup)
        # Separate from zone-type-based waiting estimate — uses actual estimated loading time
        loading_charge = 0
        if @config.respond_to?(:waiting_per_min_rate_paise) && @config.waiting_per_min_rate_paise.to_i > 0
          free_minutes = @config.respond_to?(:free_waiting_minutes) ? @config.free_waiting_minutes.to_i : 10
          actual_loading_min = [estimated_loading_min.to_i, 0].max
          chargeable_loading = [actual_loading_min - free_minutes, 0].max
          loading_charge = chargeable_loading * @config.waiting_per_min_rate_paise.to_i
        end

        # Step 4: Raw subtotal
        # Distance band shaping applies ONLY to the distance component, not base_fare.
        # Base fare is a fixed cost (driver showing up, loading) and should not be
        # scaled by distance. The distance component is the variable cost.
        band_multiplier = calculate_distance_band_multiplier(@config.vehicle_type, distance_m)
        shaped_distance = distance_component.to_f * band_multiplier
        raw_subtotal = base_fare + shaped_distance + time_component + dead_km_charge + waiting_charge + loading_charge
        
        # =====================================================================
        # INDUSTRY-STANDARD CHARGE COMPONENTS (Cogoport/ShipX patterns)
        # Now using CONFIGURABLE zone-level settings instead of hardcoded values
        # =====================================================================
        
        # 4c. Fuel Surcharge (FSC) - From zone config (industry: 8-12%, default 0)
        # Use zone-level FSC if configured, otherwise use global default
        fsc_pct = zone_pricing.fuel_surcharge_pct || FUEL_SURCHARGE_PCT
        fuel_surcharge_paise = raw_subtotal * fsc_pct
        
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
        # NOTE: zone_type_mult is applied at the END (after guardrail) for predictable admin behavior.
        # So a 0.85x zone setting reliably gives 15% off the final price, not a surprise discount.
        raw_subtotal = raw_subtotal * oda_mult
        raw_subtotal += fuel_surcharge_paise
        raw_subtotal += special_location_surcharge

        # Check calibration mode early (needed by weather/backhaul/cancellation)
        calibration_mode = ENV['PRICING_MODE'] == 'calibration'

        # =====================================================================
        # WEATHER MULTIPLIER (Phase 2) — flag-gated
        # =====================================================================
        weather_condition = nil
        weather_mult = 1.0
        monsoon_surcharge_applied = false
        if !calibration_mode && PricingRolloutFlag.enabled?('weather_pricing', city_code: @config.city_code)
          weather = RoutePricing::Services::WeatherProvider.new.current_weather(city_code: @config.city_code)
          weather_condition = weather[:condition]
          weather_mult = (@config.weather_multipliers || {})[weather[:multiplier_key]]&.to_f || 1.0
          raw_subtotal *= weather_mult

          # Monsoon surcharge: additional 15% during Jun-Sep for rain conditions
          monsoon_months = (6..9)
          rain_conditions = %w[RAIN HEAVY_RAIN]
          if rain_conditions.include?(weather_condition.to_s) &&
             monsoon_months.cover?(local_time.month) &&
             PricingRolloutFlag.enabled?('monsoon_surcharge', city_code: @config.city_code)
            raw_subtotal *= 1.15
            monsoon_surcharge_applied = true
          end
        end

        # =====================================================================
        # BACKHAUL MULTIPLIER (Phase 3) — flag-gated
        # =====================================================================
        backhaul_mult = 1.0
        if !calibration_mode && PricingRolloutFlag.enabled?('backhaul_pricing', city_code: @config.city_code)
          backhaul_mult = RoutePricing::Services::BackhaulCalculator.new.calculate(
            zone: zone_pricing.zone_info,
            time_band: time_band,
            city_code: @config.city_code,
            max_premium: @config.try(:max_backhaul_premium) || 0.20
          )
          raw_subtotal *= backhaul_mult
        end

        # =====================================================================
        # CANCELLATION RISK MULTIPLIER (Phase 6) — flag-gated
        # =====================================================================
        cancel_risk_mult = 1.0
        if !calibration_mode && PricingRolloutFlag.enabled?('cancellation_risk_pricing', city_code: @config.city_code)
          cancel_risk_mult = calculate_cancellation_risk_multiplier(zone_pricing.zone_info)
          raw_subtotal *= cancel_risk_mult
        end

        # =====================================================================
        # WEIGHT-BASED PRICING
        # =====================================================================
        weight_multiplier = calculate_weight_multiplier(weight_kg)
        raw_subtotal = raw_subtotal * weight_multiplier if weight_multiplier > 1.0

        # =====================================================================
        # 3-LAYER DYNAMIC SURGE CALCULATION
        # =====================================================================
        # v5.0: Routes with time-aware zone pricing bypass all multipliers
        # Time-specific base prices already encode time-of-day demand
        time_aware_bypass = zone_pricing.source == :zone_time_override

        # =====================================================================

        # =====================================================================
        # DYNAMIC FACTOR CALCULATION
        # =====================================================================
        if calibration_mode || time_aware_bypass
          # -----------------------------------------------------------
          # PURE CALIBRATION MODE or TIME-AWARE ZONE PRICING
          # -----------------------------------------------------------
          # We want to tune the BASE SLABS against the competitor's base.
          # The competitor's price includes their zone/demand logic, but our
          # baseline shouldn't chase their surges.
          # -----------------------------------------------------------
          traffic_multiplier = 1.0
          time_multiplier    = 1.0
          zone_multiplier    = 1.0
          h3_surge           = 1.0
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

          # 4. H3 per-hex surge (hyperlocal, higher priority than zone-level surge)
          h3_surge = resolve_h3_surge(pickup_lat, pickup_lng, time_band)

          # Use the higher of zone surge and H3 surge for the zone dimension
          effective_zone_surge = h3_surge > 1.0 ? [zone_multiplier, h3_surge].max : zone_multiplier

          # 5. Combined Surge (capped at 2.0 for safety)
          combined_surge = [traffic_multiplier * time_multiplier * effective_zone_surge, 2.0].min

          # Buffers & Margins
          variance_buffer = @config.variance_buffer_pct || 0.0

          # High-value item buffer: applies when item_value exceeds threshold
          # Uses existing PricingConfig columns (defaults to 0, no effect until configured)
          threshold = @config.try(:high_value_threshold_paise).to_i
          high_value_buffer = if item_value_paise && threshold > 0 && item_value_paise > threshold
                                [@config.try(:high_value_buffer_pct).to_f, 0.0].max
                              else
                                0.0
                              end
          
          # Margin from config (pilot: 0.0, rely on guardrail)
          margin_total = @config.min_margin_pct || 0.0
        end

        # Apply Multipliers
        multiplied = raw_subtotal * combined_surge * @config.vehicle_multiplier * @config.city_multiplier

        # =====================================================================
        # MULTIPLICATIVE CAP — prevent runaway stacking
        # =====================================================================
        all_mults = [zone_type_mult, oda_mult, weather_mult, backhaul_mult, cancel_risk_mult,
                     weight_multiplier, @config.vehicle_multiplier.to_f,
                     @config.city_multiplier.to_f]
        total_mult_effect = all_mults.reduce(1.0, :*)
        mult_cap_applied = false

        if !calibration_mode && total_mult_effect > MAX_TOTAL_MULTIPLICATIVE_EFFECT
          cap_scale = MAX_TOTAL_MULTIPLICATIVE_EFFECT / total_mult_effect
          multiplied *= cap_scale
          mult_cap_applied = true
          Rails.logger.warn(
            "[MULT_CAP] Total multiplier effect #{total_mult_effect.round(2)} exceeds " \
            "#{MAX_TOTAL_MULTIPLICATIVE_EFFECT}. Scaled down by #{cap_scale.round(3)}"
          )
        end

        # Monitor when 3+ multipliers are simultaneously active
        active_mult_names = []
        { zone_type: zone_type_mult, oda: oda_mult, weather: weather_mult,
          backhaul: backhaul_mult, cancel_risk: cancel_risk_mult, weight: weight_multiplier,
          traffic: traffic_multiplier, time_of_day: time_multiplier,
          zone_demand: zone_multiplier, h3_surge: h3_surge }.each do |name, val|
          active_mult_names << "#{name}=#{val.round(3)}" if val > 1.01
        end
        if active_mult_names.size >= 3
          Rails.logger.info("[MULTI_SURGE] #{active_mult_names.size} multipliers active: #{active_mult_names.join(', ')}")
        end

        # Apply Buffers
        subtotal_with_buffers = multiplied * (1 + variance_buffer + high_value_buffer)
        
        # Apply Margin
        price_after_margin = subtotal_with_buffers * (1 + margin_total)

        # Rounding
        if calibration_mode
          # Precise rounding for calibration
          final_price_paise = price_after_margin.round.to_i
        else
          # Standard rounding to nearest Rs 10 (1000 paise)
          # Previously used ceiling: (x+999)/1000*1000 which over-charged by up to 22%
          final_price_paise = ((price_after_margin / 1000.0).round * 1000).to_i
        end

        # =====================================================================
        # SCHEDULED BOOKING DISCOUNT
        # =====================================================================
        scheduled_discount_info = calculate_scheduled_discount(final_price_paise, quote_time)
        final_price_paise = scheduled_discount_info[:discounted_price_paise]

        # Price floor — applied before zone multiplier so discounts can legitimately go below baseline floor.
        final_price_paise = [final_price_paise, @config.min_fare_paise.to_i].max

        # =====================================================================
        # UNIT ECONOMICS (Internal - Not shown to user)
        # =====================================================================
        estimated_vendor_cost_paise = estimate_vendor_cost(
          city_code: @config.city_code,
          vehicle_type: @config.vehicle_type,
          distance_m: distance_m,
          duration_in_traffic_s: duration_in_traffic_s,
          time_band: time_band,
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          raw_subtotal: raw_subtotal
        )
        
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
        # Runs BEFORE the zone_type_mult final step, so it floors the pre-multiplier baseline.
        # =====================================================================
        guardrail_applied = false
        if !calibration_mode && margin_pct < MIN_TARGET_MARGIN_PCT
          # Bump price to achieve minimum margin
          required_price_paise = (total_cost_paise * (1 + MIN_TARGET_MARGIN_PCT / 100.0)).ceil

          # Round up to nearest Rs 10 for guardrail (ceiling to preserve margin)
          guardrail_price_paise = ((required_price_paise / 1000.0).ceil * 1000).to_i

          # Log the adjustment
          Rails.logger.warn(
            "[UNIT_ECON_GUARDRAIL] Price bumped: " \
            "#{final_price_paise/100.0} → #{guardrail_price_paise/100.0} " \
            "(margin was #{margin_pct}%, needed #{MIN_TARGET_MARGIN_PCT}%)"
          )

          # Apply guardrail
          final_price_paise = guardrail_price_paise.to_i
          guardrail_applied = true

          # Recalculate with new price
          pg_fee_paise = (final_price_paise * 0.02).round
          total_cost_paise = estimated_vendor_cost_paise + pg_fee_paise + support_buffer_paise + maps_cost_paise
          margin_paise = final_price_paise - total_cost_paise
          margin_pct = total_cost_paise > 0 ? ((margin_paise.to_f / total_cost_paise) * 100).round(1) : 0.0
        end

        # Apply zone-level multiplier (launch discount or premium surge) as a FINAL step
        # — after guardrail — so the admin gets predictable ±% vs baseline.
        if zone_type_mult.to_f != 1.0
          final_price_paise = (final_price_paise * zone_type_mult).round
          pg_fee_paise = (final_price_paise * 0.02).round
          total_cost_paise = estimated_vendor_cost_paise + pg_fee_paise + support_buffer_paise + maps_cost_paise
          margin_paise = final_price_paise - total_cost_paise
          margin_pct = total_cost_paise > 0 ? ((margin_paise.to_f / total_cost_paise) * 100).round(1) : 0.0
        end

        # =====================================================================
        # MAX FARE CEILING (safety cap — never charge more than configured ceiling)
        # =====================================================================
        max_fare_cap_applied = false
        max_fare_limit = @config.try(:max_fare_paise).to_i
        if max_fare_limit > 0 && final_price_paise > max_fare_limit
          Rails.logger.warn(
            "[MAX_FARE_CAP] Price capped: ₹#{final_price_paise/100.0} → ₹#{max_fare_limit/100.0} " \
            "(#{@config.vehicle_type} in #{@config.city_code})"
          )
          final_price_paise = max_fare_limit
          max_fare_cap_applied = true
          pg_fee_paise = (final_price_paise * 0.02).round
          total_cost_paise = estimated_vendor_cost_paise + pg_fee_paise + support_buffer_paise + maps_cost_paise
          margin_paise = final_price_paise - total_cost_paise
          margin_pct = total_cost_paise > 0 ? ((margin_paise.to_f / total_cost_paise) * 100).round(1) : 0.0
        elsif max_fare_limit > 0 && final_price_paise > (max_fare_limit * 0.9)
          Rails.logger.info(
            "[MAX_FARE_CAP] Approaching ceiling: ₹#{final_price_paise/100.0} " \
            "(#{((final_price_paise.to_f / max_fare_limit) * 100).round(1)}% of ₹#{max_fare_limit/100.0})"
          )
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
          guardrail_applied: guardrail_applied,
          max_fare_cap_applied: max_fare_cap_applied
        }
        
        # =====================================================================

        # Build detailed breakdown
        # Build human-readable surge reasons
        surge_reasons = build_surge_reasons(
          traffic_multiplier: traffic_multiplier,
          time_multiplier: time_multiplier,
          zone_multiplier: zone_multiplier,
          h3_surge: h3_surge,
          time_band: time_band,
          calibration_mode: calibration_mode
        )

        breakdown = {
          calibration_mode: calibration_mode,
          pricing_source: zone_pricing.source,
          pricing_mode: zone_pricing.pricing_mode,
          zone_info: zone_pricing.zone_info,
          base_fare: base_fare,
          chargeable_distance_m: chargeable_m,
          distance_component: distance_component,
          # Per-minute pricing (Phase A)
          time_component: time_component.round,
          per_min_rate_paise: per_min_rate,
          # Dead-km charge (Phase A)
          dead_km_charge: dead_km_charge.round,
          estimated_pickup_distance_m: @last_estimated_pickup_distance_m || 0,
          # Waiting charge (Phase 5)
          waiting_charge: waiting_charge.round,
          # Loading charge (goods delivery: explicit loading time at pickup)
          loading_charge: loading_charge.round,
          distance_band_multiplier: band_multiplier,
          shaped_distance_component: shaped_distance.round,
          slab_pricing_used: @config.pricing_distance_slabs.any?,
          # Industry-standard components (Cogoport/ShipX)
          fuel_surcharge_pct: fsc_pct,
          fuel_surcharge_paise: fuel_surcharge_paise.round,
          zone_type_multiplier: zone_type_mult.round(3),
          oda_multiplier: oda_mult.round(3),
          special_location_surcharge_paise: special_location_surcharge,
          # Weather (Phase 2)
          weather_condition: weather_condition,
          weather_multiplier: weather_mult.round(3),
          monsoon_surcharge_applied: monsoon_surcharge_applied,
          # Backhaul (Phase 3)
          backhaul_multiplier: backhaul_mult.round(3),
          # Cancellation risk (Phase 6)
          cancellation_risk_multiplier: cancel_risk_mult.round(3),
          # Route segment pricing (Phase 1)
          segment_pricing_used: segment_pricing_used,
          # Weight-based pricing
          weight_kg: weight_kg,
          weight_multiplier: weight_multiplier.round(3),
          raw_subtotal: raw_subtotal.round,
          # Surge transparency
          surge_reasons: surge_reasons,
          # 3-layer surge breakdown
          traffic_multiplier: traffic_multiplier.round(3),
          time_multiplier: time_multiplier.round(3),
          zone_multiplier: zone_multiplier.round(3),
          h3_surge: h3_surge.round(3),
          combined_surge: combined_surge.round(3),
          # Traffic details
          traffic_ratio: (duration_in_traffic_s && duration_s && duration_s > 0) ? 
                         (duration_in_traffic_s.to_f / duration_s).round(2) : nil,
          duration_s: duration_s,
          duration_in_traffic_s: duration_in_traffic_s,
          # Other multipliers
          vehicle_multiplier: @config.vehicle_multiplier.to_f,
          city_multiplier: @config.city_multiplier.to_f,
          after_multipliers: multiplied.round,
          variance_buffer: variance_buffer,
          high_value_buffer: high_value_buffer,
          subtotal_with_buffers: subtotal_with_buffers.round,
          margin_guardrail: margin_total,
          price_after_margin: price_after_margin.round,
          scheduled_discount: scheduled_discount_info[:applied] ? scheduled_discount_info : nil,
          # Multiplicative cap
          total_multiplicative_effect: total_mult_effect.round(3),
          mult_cap_applied: mult_cap_applied,
          final_price: final_price_paise
        }

        # Price summary — human-friendly cost breakdown
        surge_impact = (multiplied - raw_subtotal).round
        breakdown[:price_summary] = {
          base: base_fare,
          distance: shaped_distance.round,
          time_charge: time_component.round,
          dead_km: dead_km_charge.round,
          waiting: waiting_charge.round,
          loading: loading_charge.round,
          subtotal: raw_subtotal.round,
          surge_impact: surge_impact,
          final: final_price_paise
        }

        # Price drivers — top factors affecting this quote
        breakdown[:price_drivers] = compute_price_drivers(
          raw_subtotal, all_mults,
          zone_type_mult: zone_type_mult, oda_mult: oda_mult, weather_mult: weather_mult,
          backhaul_mult: backhaul_mult, cancel_risk_mult: cancel_risk_mult,
          weight_multiplier: weight_multiplier, traffic_multiplier: traffic_multiplier,
          time_multiplier: time_multiplier, zone_multiplier: zone_multiplier,
          h3_surge: h3_surge, band_multiplier: band_multiplier,
          vehicle_multiplier: @config.vehicle_multiplier.to_f,
          city_multiplier: @config.city_multiplier.to_f
        )

        breakdown[:unit_economics] = unit_economics if ENV['PRICING_EXPOSE_INTERNALS'] == 'true'

        # =====================================================================
        # WARNINGS (advisory flags for the client — app decides how to surface)
        # =====================================================================
        warnings = []

        # Delivery-to-item-value ratio: delivery shouldn't eat too much of the item value.
        if item_value_paise && item_value_paise > 0
          ratio_threshold = @config.try(:high_value_ratio_threshold).to_f
          ratio_threshold = 0.40 if ratio_threshold <= 0
          ratio = final_price_paise.to_f / item_value_paise.to_f
          if ratio > ratio_threshold
            warnings << {
              code: 'high_delivery_ratio',
              ratio: ratio.round(3),
              threshold: ratio_threshold,
              message: "Delivery is #{(ratio * 100).round(1)}% of item value (₹#{final_price_paise/100.0} / ₹#{item_value_paise/100.0})"
            }
          end
        end

        # Max fare cap was hit: client might want to show a "heavy route" message.
        if max_fare_cap_applied
          warnings << {
            code: 'max_fare_capped',
            message: "Price capped at configured ceiling for #{@config.vehicle_type}"
          }
        end

        breakdown[:warnings] = warnings
        deep_freeze(breakdown)

        {
          final_price_paise: final_price_paise,
          breakdown: breakdown,
          warnings: warnings
        }
      end

      private

      # Layer 2: DELETED - Replaced by PricingConfig#calculate_surge_multiplier in v3.0
      # Old calculate_time_multiplier method removed - now handled by PricingConfig

      # Layer 1: Real-time traffic multiplier using smooth curve
      def calculate_traffic_multiplier(duration_in_traffic_s, duration_s)
        return 1.0 if duration_in_traffic_s.nil? || duration_s.nil? || duration_s <= 0

        traffic_ratio = duration_in_traffic_s.to_f / duration_s

        # Sanity check: ignore impossibly low ratios
        return 1.0 if traffic_ratio < 0.9
        # Extreme congestion (>3x normal): apply max multiplier
        return TRAFFIC_MAX_MULTIPLIER if traffic_ratio > 3.0

        # Smooth curve: y = 1 + 0.5 * (x - 1)^0.8, capped at TRAFFIC_MAX_MULTIPLIER
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

      # H3 per-hex surge lookup (hyperlocal granularity)
      def resolve_h3_surge(lat, lng, time_band)
        return 1.0 unless lat && lng
        resolver = RoutePricing::Services::H3SurgeResolver.new(@config.city_code)
        resolver.resolve(lat, lng, time_band: time_band)
      rescue StandardError
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
          slab_end_m = slab[:max_distance_m]

          meters_in_slab = if distance_m <= slab_start_m
                             0
                           elsif slab_end_m.nil?
                             distance_m - slab_start_m
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
        # Use sort_by to avoid additional SQL query when association is preloaded via includes
        slabs = @config.pricing_distance_slabs.sort_by(&:min_distance_m)
        
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
          slab_end_m = slab.max_distance_m

          meters_in_slab = if distance_m <= slab_start_m
                             0
                           elsif slab_end_m.nil?
                             distance_m - slab_start_m
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

      def calculate_distance_band_multiplier(vehicle_type, distance_m)
        # Distance band multipliers for shaping the price curve
        # Tuned based on competitor benchmark analysis:
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

        # Tuned multipliers for benchmark alignment (v6.1 calibration)
        category = RoutePricing::VehicleCategories.category_for(vehicle_type)
        case category
        when :small
          # Small vehicles: No micro discount — micro deliveries have highest fixed-cost ratio
          { micro: 1.00, short: 1.00, medium: 1.05, long: 1.00 }[band]
        when :mid
          # Mid vehicles: Moderate micro discount (operational efficiency at short range)
          { micro: 0.90, short: 1.00, medium: 1.05, long: 1.00 }[band]
        when :heavy
          # Heavy vehicles: Minimal micro discount (fixed costs dominate)
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
      
      # Build human-readable surge reasons for API transparency
      def build_surge_reasons(traffic_multiplier:, time_multiplier:, zone_multiplier:, h3_surge: 1.0, time_band:, calibration_mode:)
        return [{ code: 'calibration', label: 'Calibration mode active', multiplier: 1.0 }] if calibration_mode

        reasons = []

        if traffic_multiplier > 1.01
          reasons << { code: 'traffic', label: 'High traffic detected', multiplier: traffic_multiplier.round(3) }
        end

        if time_multiplier > 1.01
          label = case time_band
                  when 'evening' then 'Evening peak pricing'
                  when 'morning' then 'Morning rush pricing'
                  else 'Time-based pricing'
                  end
          reasons << { code: 'time_of_day', label: label, multiplier: time_multiplier.round(3) }
        end

        if h3_surge > 1.01
          reasons << { code: 'h3_surge', label: 'Hyperlocal demand surge', multiplier: h3_surge.round(3) }
        end

        if zone_multiplier > 1.01
          reasons << { code: 'zone_demand', label: 'High demand area', multiplier: zone_multiplier.round(3) }
        elsif zone_multiplier < 0.99
          reasons << { code: 'zone_discount', label: 'Area discount applied', multiplier: zone_multiplier.round(3) }
        end

        reasons << { code: 'standard', label: 'Standard pricing', multiplier: 1.0 } if reasons.empty?

        reasons
      end

      # Compute price drivers — categorized multipliers with estimated paise impact
      def compute_price_drivers(raw_subtotal, _all_mults, **mults)
        drivers = [
          { name: 'distance_band',  category: :base_calc,          mult: mults[:band_multiplier] },
          { name: 'zone_type',      category: :industry_standard,  mult: mults[:zone_type_mult] },
          { name: 'oda',            category: :industry_standard,  mult: mults[:oda_mult] },
          { name: 'weather',        category: :dynamic_market,     mult: mults[:weather_mult] },
          { name: 'backhaul',       category: :dynamic_market,     mult: mults[:backhaul_mult] },
          { name: 'cancel_risk',    category: :dynamic_market,     mult: mults[:cancel_risk_mult] },
          { name: 'weight',         category: :base_calc,          mult: mults[:weight_multiplier] },
          { name: 'traffic',        category: :dynamic_market,     mult: mults[:traffic_multiplier] },
          { name: 'time_of_day',    category: :dynamic_market,     mult: mults[:time_multiplier] },
          { name: 'zone_demand',    category: :dynamic_market,     mult: mults[:zone_multiplier] },
          { name: 'h3_surge',       category: :dynamic_market,     mult: mults[:h3_surge] },
          { name: 'vehicle',        category: :config_level,       mult: mults[:vehicle_multiplier] },
          { name: 'city',           category: :config_level,       mult: mults[:city_multiplier] }
        ]

        active = drivers.select { |d| (d[:mult] - 1.0).abs > 0.005 }
        active.each { |d| d[:impact_paise] = (raw_subtotal * (d[:mult] - 1.0)).round }
        top_3 = active.sort_by { |d| -d[:impact_paise].abs }.first(3)

        {
          active_multiplier_count: active.size,
          total_multiplicative_effect: drivers.map { |d| d[:mult] }.reduce(1.0, :*).round(3),
          top_3_drivers: top_3.map { |d| { name: d[:name], category: d[:category], multiplier: d[:mult].round(3), impact_paise: d[:impact_paise] } },
          by_category: drivers.group_by { |d| d[:category] }.transform_values { |ds| ds.map { |d| { name: d[:name], multiplier: d[:mult].round(3) } } }
        }
      end

      # Scheduled booking discount: future bookings get a configurable discount
      def calculate_scheduled_discount(price_paise, quote_time)
        threshold_hours = @config.try(:scheduled_threshold_hours) || 2
        discount_pct = @config.try(:scheduled_discount_pct).to_f

        if discount_pct > 0 && quote_time > Time.current + threshold_hours.hours
          discount_paise = (price_paise * discount_pct / 100.0).round
          {
            applied: true,
            discount_pct: discount_pct,
            discount_paise: discount_paise,
            original_price_paise: price_paise,
            discounted_price_paise: price_paise - discount_paise,
            threshold_hours: threshold_hours
          }
        else
          { applied: false, discounted_price_paise: price_paise }
        end
      end

      # Weight-based multiplier using configurable tiers from PricingConfig
      def calculate_weight_multiplier(weight_kg)
        return 1.0 unless weight_kg.present? && weight_kg > 0

        tiers = @config.try(:weight_multiplier_tiers)
        tiers = [
          { 'max_kg' => 15, 'mult' => 1.0 },
          { 'max_kg' => 50, 'mult' => 1.1 },
          { 'max_kg' => 200, 'mult' => 1.2 },
          { 'max_kg' => nil, 'mult' => 1.4 }
        ] if tiers.blank?

        tiers.each do |tier|
          max = tier['max_kg']
          if max.nil? || weight_kg <= max
            mult = tier['mult'].to_f
            return mult > 0 ? mult : 1.0
          end
        end

        1.0
      end

      # Dead-km charge: cost for driver to reach pickup location
      def calculate_dead_km_charge(pickup_lat, pickup_lng, city_code, time_band)
        return 0 unless @config.dead_km_enabled

        estimated_m = resolve_pickup_distance(pickup_lat, pickup_lng, city_code, time_band)
        @last_estimated_pickup_distance_m = estimated_m
        free_radius = @config.free_pickup_radius_m
        return 0 if free_radius <= 0 || estimated_m <= free_radius

        excess_m = estimated_m - free_radius
        (excess_m / 1000.0) * @config.dead_km_per_km_rate_paise
      end

      # Estimate how far a driver must travel to reach pickup.
      # Phase 1: zone-type defaults. Upgraded to H3 in Phase C.
      def resolve_pickup_distance(pickup_lat, pickup_lng, city_code, time_band)
        # Try H3 supply density first (Phase C upgrade)
        if defined?(H3) && defined?(H3SupplyDensity)
          begin
            h3_r7 = H3.from_geo_coordinates([pickup_lat.to_f, pickup_lng.to_f], 7).to_s(16)
            density = H3SupplyDensity.for_cell(h3_r7, city_code, time_band).first
            return density.avg_pickup_distance_m if density
          rescue StandardError => e
            Rails.logger.debug("H3 pickup distance lookup failed: #{e.message}")
          end
        end

        # Fallback: zone-type defaults
        zone = Zone.find_containing(city_code, pickup_lat, pickup_lng)
        return 3000 unless zone

        case zone.zone_type
        when 'tech_corridor', 'business_cbd' then 2000
        when 'residential_dense', 'residential_mixed' then 3000
        when 'residential_growth' then 3500
        when 'airport_logistics' then 5000
        when 'industrial', 'outer_ring' then 4000
        else 3000
        end
      end

      # Waiting/loading charge (Phase 5)
      # Estimates customer waiting time by zone type and charges for excess wait
      def calculate_waiting_charge(zone_info)
        per_min_rate = @config.try(:waiting_per_min_rate_paise).to_i
        return 0 if per_min_rate <= 0

        free_minutes = @config.try(:free_waiting_minutes) || 10

        # Estimate waiting time by zone type
        zone_type = zone_info&.dig(:pickup_type) || 'default'
        estimated_wait_min = case zone_type
                             when 'tech_corridor'      then 5
                             when 'business_cbd'       then 8
                             when 'residential_dense'  then 12
                             when 'residential_mixed'  then 10
                             when 'residential_growth' then 12
                             when 'airport_logistics'  then 3
                             when 'industrial'         then 6
                             when 'outer_ring'         then 8
                             else 8
                             end

        chargeable_wait = [0, estimated_wait_min - free_minutes].max
        chargeable_wait * per_min_rate
      end

      # Cancellation risk multiplier (Phase 6)
      # Higher cancellation zones get a small premium to absorb risk
      def calculate_cancellation_risk_multiplier(zone_info)
        pickup_zone_code = zone_info&.dig(:pickup_zone)
        return 1.0 unless pickup_zone_code

        zone = Zone.find_by(zone_code: pickup_zone_code, city: @config.city_code)
        cancel_rate = zone&.cancellation_rate_pct
        return 1.0 unless cancel_rate && cancel_rate > 0

        # cancel_risk_mult = 1.0 + (cancel_rate / 100.0) * 0.5
        # 15% cancel → 1.075x, 5% → 1.025x
        1.0 + (cancel_rate / 100.0) * 0.5
      rescue StandardError
        1.0
      end

      # Route segment distance component (Phase 1)
      # Uses per-zone rates for each segment of the route
      def calculate_segment_distance_component(route_segments, time_band)
        total_paise = 0

        route_segments.each do |segment|
          zone = segment[:zone] || segment['zone']
          distance_m = (segment[:distance_m] || segment['distance_m']).to_f
          next if distance_m <= 0

          # Look up zone-specific per-km rate
          per_km_rate = resolve_segment_zone_rate(zone, @config.vehicle_type, time_band)
          km = distance_m / 1000.0
          total_paise += (km * per_km_rate).round
        end

        total_paise
      end

      # Look up per-km rate for a zone segment
      def resolve_segment_zone_rate(zone_code, vehicle_type, time_band)
        return @config.per_km_rate_paise unless zone_code

        zone = Zone.find_by(zone_code: zone_code, city: @config.city_code)
        return @config.per_km_rate_paise unless zone

        zvp = ZoneVehiclePricing.find_by(zone: zone, vehicle_type: vehicle_type, active: true)
        return @config.per_km_rate_paise unless zvp

        # Try time-band specific rate first
        if time_band.present?
          tp = zvp.time_pricings.detect { |t| t.active && t.time_band == time_band }
          unless tp
            fallback = RoutePricing::Services::TimeBandResolver.fallback_band(time_band)
            tp = zvp.time_pricings.detect { |t| t.active && t.time_band == fallback } if fallback != time_band
          end
          return tp.per_km_rate_paise if tp
        end

        zvp.per_km_rate_paise
      rescue StandardError
        @config.per_km_rate_paise
      end

      # ODA Multiplier using zone-level config (preferred over hardcoded)
      # Uses is_oda flag and oda_surcharge_pct from Zone model
      def calculate_oda_multiplier_from_config(oda_config)
        return 1.0 unless oda_config && oda_config[:both_oda]

        # Convert percentage to multiplier (e.g., 5% → 1.05)
        surcharge_pct = oda_config[:surcharge_pct] || 5.0
        1.0 + (surcharge_pct / 100.0)
      end

      # Estimate vendor cost using VendorPayoutCalculator if available,
      # falling back to raw_subtotal (our own price) if no rate card exists.
      def estimate_vendor_cost(city_code:, vehicle_type:, distance_m:, duration_in_traffic_s:, time_band:, pickup_lat:, pickup_lng:, raw_subtotal:)
        result = VendorPayoutCalculator.new.calculate(
          city_code: city_code,
          vehicle_type: vehicle_type,
          distance_m: distance_m,
          duration_in_traffic_s: duration_in_traffic_s,
          time_band: time_band,
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng
        )
        if result[:predicted_paise]
          result[:predicted_paise]
        else
          (raw_subtotal * vendor_cost_ratio).round
        end
      rescue StandardError => e
        Rails.logger.warn("[VENDOR_COST] Fallback to #{(vendor_cost_ratio * 100).round}% of raw_subtotal: #{e.message}")
        (raw_subtotal * vendor_cost_ratio).round
      end

      # Vehicle-category-aware vendor cost ratio (industry benchmarks)
      def vendor_cost_ratio
        category = RoutePricing::VehicleCategories.category_for(@config.vehicle_type)
        case category
        when :small then 0.78  # Two-wheeler/scooter: high driver payout ratio
        when :mid   then 0.70  # 3W/Ace/Pickup: moderate
        when :heavy then 0.62  # Eeco/407/Canter: lower driver share, higher platform margin
        else 0.70
        end
      end

      # Cancellation fee model (Phase 6)
      # Returns fee in paise based on cancellation stage
      def calculate_cancellation_fee(quote_price_paise, cancellation_stage)
        case cancellation_stage
        when :before_acceptance then 0
        when :after_acceptance then (quote_price_paise * 0.20).round  # 20%
        when :in_transit then (quote_price_paise * 0.50).round  # 50%
        else 0
        end
      end

      # Multi-stop surcharge (not yet wired into main calculate flow)
      # Returns surcharge in paise for additional stops beyond the first drop
      def calculate_multi_stop_surcharge(additional_stops)
        return 0 unless additional_stops.to_i > 0
        additional_stops.to_i * 2000  # ₹20 per additional stop (2000 paise)
      end

      # Recursively freeze a hash and all nested values
      def deep_freeze(obj)
        case obj
        when Hash
          obj.each_value { |v| deep_freeze(v) }
          obj.freeze
        when Array
          obj.each { |v| deep_freeze(v) }
          obj.freeze
        else
          obj.freeze if obj.respond_to?(:freeze)
        end
        obj
      end
    end
  end
end
