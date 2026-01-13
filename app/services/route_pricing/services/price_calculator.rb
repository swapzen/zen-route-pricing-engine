# frozen_string_literal: true

module RoutePricing
  module Services
    class PriceCalculator
      def initialize(config:)
        @config = config
      end

      def calculate(distance_m:, item_value_paise: nil, duration_in_traffic_s: nil, duration_s: nil, quote_time: Time.current)
        # Step 1: Base fare (max of base_fare and min_fare)
        base_fare = [@config.base_fare_paise, @config.min_fare_paise].max

        # Step 2: Chargeable distance
        chargeable_m = [0, distance_m - @config.base_distance_m].max

        # Step 3: Distance component
        chargeable_km = (chargeable_m + 999) / 1000  # Integer division, rounds up
        distance_component = chargeable_km * @config.per_km_rate_paise

        # Step 4: Raw subtotal
        raw_subtotal = base_fare + distance_component

        # Step 5: Calculate dynamic surge multiplier
        # 🛑 CRITICAL FIX: Use resolver's duration_s, not recalculation
        traffic_ratio = nil
        if duration_in_traffic_s && duration_s && duration_s > 0
          traffic_ratio = duration_in_traffic_s.to_f / duration_s
          
          # 🔒 Sanity check: reject impossible traffic ratios
          if traffic_ratio < 0.8 || traffic_ratio > 3.0
            Rails.logger.warn("Traffic ratio #{traffic_ratio} out of bounds, ignoring")
            traffic_ratio = nil
          end
        end

        # 🛑 CRITICAL TIME ZONE FIX: Convert UTC to city local time
        timezone = @config.respond_to?(:timezone) ? @config.timezone : 'Asia/Kolkata'
        local_time = quote_time.in_time_zone(timezone)

        surge_multiplier = @config.calculate_surge_multiplier(
          time: local_time,  # Pass local time, not UTC
          traffic_ratio: traffic_ratio
        )

        # 🔒 Cap surge at 2.0× to prevent freak configs or admin mistakes
        surge_multiplier = [surge_multiplier, 2.0].min

        # Step 6: Apply multipliers (using BigDecimal for precision, then round)
        # 🛑 CRITICAL FIX: Use .round instead of .to_i to avoid silent underpricing
        multiplied = (
          BigDecimal(raw_subtotal.to_s) *
          BigDecimal(@config.vehicle_multiplier.to_s) *
          BigDecimal(@config.city_multiplier.to_s) *
          BigDecimal(surge_multiplier.to_s)
        ).round(0).to_i

        # Step 7: Variance buffer
        variance_raw = (multiplied * @config.variance_buffer_pct).round
        variance_buffer = [
          [@config.variance_buffer_min_paise, variance_raw].max,
          @config.variance_buffer_max_paise
        ].min

        # Step 8: High-value buffer
        # Note: Buffer based on item value (insurance/handling risk cost)
        high_value_buffer = 0
        if item_value_paise && item_value_paise > @config.high_value_threshold_paise
          high_value_raw = (item_value_paise * @config.high_value_buffer_pct).round
          high_value_buffer = [@config.high_value_buffer_min_paise, high_value_raw].max
        end

        # Step 9: Subtotal with buffers
        subtotal_with_buffers = multiplied + variance_buffer + high_value_buffer

        # Step 10: Minimum margin guardrail (explicit markup calculation)
        # This ensures minimum profit margin is always applied
        # 🛑 INVARIANT: final_price_paise >= expected vendor cost (Porter)
        # All buffers and margins exist to guarantee we never underprice
        margin_pct_amount = (subtotal_with_buffers * @config.min_margin_pct).round
        margin_total = margin_pct_amount + @config.min_margin_flat_paise
        
        # Apply margin guardrail (clearer intent)
        price_after_margin = [
          subtotal_with_buffers,
          subtotal_with_buffers + margin_total
        ].max

        # Step 11: Round up to nearest ₹10 (1000 paise)
        final_price_paise = ((price_after_margin + 999) / 1000) * 1000

        # 🔒 Emergency price floor: Never go below minimum fare
        final_price_paise = [final_price_paise, @config.min_fare_paise].max

        # Build breakdown for transparency
        breakdown = {
          base_fare: base_fare,
          chargeable_distance_m: chargeable_m,
          chargeable_km: chargeable_km,
          distance_component: distance_component,
          raw_subtotal: raw_subtotal,
          surge_multiplier_applied: surge_multiplier.round(3),
          traffic_ratio: traffic_ratio&.round(2),
          duration_s: duration_s,
          duration_in_traffic_s: duration_in_traffic_s,
          vehicle_multiplier: @config.vehicle_multiplier.to_f,
          city_multiplier: @config.city_multiplier.to_f,
          after_multipliers: multiplied,
          variance_buffer: variance_buffer,
          high_value_buffer: high_value_buffer,
          subtotal_with_buffers: subtotal_with_buffers,
          margin_guardrail: margin_total,
          price_after_margin: price_after_margin,
          final_price: final_price_paise
        }.freeze  # 🔒 Prevent mutation

        {
          final_price_paise: final_price_paise,
          breakdown: breakdown
        }
      end
    end
  end
end
