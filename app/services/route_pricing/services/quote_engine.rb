# frozen_string_literal: true

module RoutePricing
  module Services
    class QuoteEngine
      # Allow injecting a mock resolver for testing
      def initialize(route_resolver: RouteResolver.new)
        @route_resolver = route_resolver
      end

      def create_quote(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, item_value_paise: nil, request_id: nil, quote_time: Time.current, weight_kg: nil, merchant_id: nil)
        # 0. Compute H3 indices for caching and logging
        h3_indices = compute_h3_indices(pickup_lat, pickup_lng, drop_lat, drop_lng)
        pickup_h3_r8 = h3_indices[:pickup_h3_r8]
        drop_h3_r8 = h3_indices[:drop_h3_r8]
        pickup_h3_r7 = h3_indices[:pickup_h3_r7]
        drop_h3_r7 = h3_indices[:drop_h3_r7]

        # 0b. H3-aware pricing cache: cache the PRICING RESULT (price + breakdown)
        # but NOT the quote_id — each request must create its own PricingQuote for audit.
        time_bucket = (Time.current.to_i / 7200)
        local_time = quote_time.in_time_zone('Asia/Kolkata')
        time_band_for_cache = RoutePricing::Services::TimeBandResolver.resolve(local_time)

        pricing_cache_key = nil
        cached_pricing = nil
        if pickup_h3_r8 && drop_h3_r8
          pricing_cache_key = "qp:#{city_code}:#{pickup_h3_r8}:#{drop_h3_r8}:#{vehicle_type}:#{time_band_for_cache}:#{time_bucket}"
          cached_pricing = Rails.cache.read(pricing_cache_key)
        end

        # 1. Fetch current config
        config = PricingConfig.current_version(city_code, vehicle_type)
        return { error: 'Config not found for city/vehicle combination', code: 404 } unless config

        # 2. Resolve route (use Directions API for segment pricing if enabled)
        route_segments = nil
        segment_pricing_enabled = PricingRolloutFlag.enabled?('route_segment_pricing', city_code: city_code)

        if segment_pricing_enabled
          route_data = @route_resolver.resolve_with_segments(
            pickup_lat: pickup_lat,
            pickup_lng: pickup_lng,
            drop_lat: drop_lat,
            drop_lng: drop_lng,
            city_code: city_code,
            vehicle_type: vehicle_type
          )

          # Segment the route into zone-based segments
          if route_data[:steps].present?
            segmenter = RouteZoneSegmenter.new(city_code: city_code)
            route_segments = segmenter.segment_route(steps: route_data[:steps])
            route_segments = route_segments.map { |s| { zone: s.zone, distance_m: s.distance_m, start_point: s.start_point, end_point: s.end_point } }
          end
        else
          route_data = @route_resolver.resolve(
            pickup_lat: pickup_lat,
            pickup_lng: pickup_lng,
            drop_lat: drop_lat,
            drop_lng: drop_lng,
            city_code: city_code,
            vehicle_type: vehicle_type
          )
        end

        # 2b. Validate route data — abort early if Google Maps failed
        if route_data.nil?
          return { error: 'Route resolution failed: no data returned', code: 502 }
        end
        if route_data[:error]
          return { error: "Route resolution failed: #{route_data[:error]}", code: 502 }
        end
        if route_data[:distance_m].nil? || route_data[:distance_m] <= 0
          return { error: 'Route resolution failed: invalid distance', code: 502 }
        end

        # 3. Calculate price (pass coordinates for zone multiplier + quote_time for v3.0)
        calculator = PriceCalculator.new(config: config)
        pricing_result = calculator.calculate(
          distance_m: route_data[:distance_m],
          duration_s: route_data[:duration_s],
          duration_in_traffic_s: route_data[:duration_in_traffic_s],
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          item_value_paise: item_value_paise,
          quote_time: quote_time,
          weight_kg: weight_kg,
          route_segments: route_segments
        )
        pricing_version = "v#{config.version}"

        # Dynamic quote validity: higher surge = shorter validity window
        combined_surge = pricing_result.dig(:breakdown, :combined_surge) || 1.0
        validity_minutes = case
                           when combined_surge > 1.3 then 5
                           when combined_surge > 1.1 then 8
                           else config.try(:quote_validity_minutes) || 15
                           end
        valid_until = Time.current + validity_minutes.minutes

        # 3b. Vendor payout prediction (two-sided pricing)
        vendor_prediction = predict_vendor_payout(
          city_code: city_code,
          vehicle_type: vehicle_type,
          distance_m: route_data[:distance_m],
          duration_in_traffic_s: route_data[:duration_in_traffic_s],
          time_band: pricing_result.dig(:breakdown, :zone_info, :time_band),
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng
        )

        # 3c. Apply merchant policies if merchant_id present
        merchant_adjustments = nil
        if merchant_id.present?
          merchant_result = apply_merchant_policies(merchant_id, pricing_result[:final_price_paise],
                                                    city_code: city_code, vehicle_type: vehicle_type)
          if merchant_result
            pricing_result[:final_price_paise] = merchant_result[:final_price_paise]
            merchant_adjustments = merchant_result[:adjustments]
          end
        end

        # 4. Persist quote
        vendor_attrs = build_vendor_quote_attrs(pricing_result[:final_price_paise], vendor_prediction)
        h3_attrs = build_h3_quote_attrs(pickup_h3_r8, drop_h3_r8, pickup_h3_r7, drop_h3_r7, pricing_result)
        extra_attrs = build_extra_quote_attrs(pricing_result, route_segments)
        quote = PricingQuote.create!(
          request_id: request_id,
          city_code: city_code,
          vehicle_type: vehicle_type,
          pickup_raw_lat: pickup_lat,
          pickup_raw_lng: pickup_lng,
          drop_raw_lat: drop_lat,
          drop_raw_lng: drop_lng,
          pickup_norm_lat: route_data[:pickup_norm][:lat],
          pickup_norm_lng: route_data[:pickup_norm][:lng],
          drop_norm_lat: route_data[:drop_norm][:lat],
          drop_norm_lng: route_data[:drop_norm][:lng],
          distance_m: route_data[:distance_m],
          duration_s: route_data[:duration_s],
          route_provider: route_data[:provider],
          route_cache_key: route_data[:cache_key],
          price_paise: pricing_result[:final_price_paise],
          price_confidence: route_data[:provider] == 'google' ? 'high' : 'estimated',
          pricing_version: pricing_version,
          breakdown_json: pricing_result[:breakdown],
          valid_until: valid_until,
          weight_kg: weight_kg,
          is_scheduled: pricing_result.dig(:breakdown, :scheduled_discount).present?,
          scheduled_for: quote_time > Time.current ? quote_time : nil,
          **vendor_attrs,
          **h3_attrs,
          **extra_attrs
        )

        # 5. Return formatted response
        result = {
          success: true,
          code: 200,
          quote_id: quote.id,
          price_paise: quote.price_paise,
          price_inr: quote.price_inr,
          distance_m: route_data[:distance_m],
          duration_s: route_data[:duration_s],
          duration_in_traffic_s: route_data[:duration_in_traffic_s],
          pricing_version: pricing_version,
          confidence: quote.price_confidence,
          provider: route_data[:provider],
          valid_until: quote.valid_until&.iso8601,
          expires_in_seconds: quote.remaining_seconds,
          breakdown: pricing_result[:breakdown]
        }

        # Add merchant adjustments to response
        result[:merchant_adjustments] = merchant_adjustments if merchant_adjustments&.any?

        # Add H3 context to response if available
        if pickup_h3_r8 || drop_h3_r8
          result[:h3_context] = {
            pickup_hex: pickup_h3_r8,
            drop_hex: drop_h3_r8,
            resolution: 8
          }
        end

        # 5b. Shadow model scoring (non-blocking)
        run_shadow_model(quote, pricing_result, city_code, vehicle_type)

        # 5c. Demand tracking (fire-and-forget)
        track_demand(city_code, pickup_h3_r7)

        # Cache the PRICING data (not quote_id) for H3-based caching
        if pricing_cache_key
          Rails.cache.write(pricing_cache_key, {
            price_paise: quote.price_paise,
            distance_m: route_data[:distance_m],
            duration_s: route_data[:duration_s],
            duration_in_traffic_s: route_data[:duration_in_traffic_s],
            pricing_version: pricing_version,
            confidence: quote.price_confidence,
            provider: route_data[:provider],
            breakdown: pricing_result[:breakdown]
          }, expires_in: 2.hours)
        end

        result
      rescue StandardError => e
        Rails.logger.error("QuoteEngine error: #{e.message}\n#{e.backtrace.join("\n")}")
        { error: e.message, code: 500 }
      end

      # Create quotes for all vehicle types with a single route resolution
      def create_multi_quote(city_code:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, item_value_paise: nil, request_id: nil, quote_time: Time.current, weight_kg: nil)
        # 0. Compute H3 indices for logging
        h3_indices = compute_h3_indices(pickup_lat, pickup_lng, drop_lat, drop_lng)
        pickup_h3_r8 = h3_indices[:pickup_h3_r8]
        drop_h3_r8 = h3_indices[:drop_h3_r8]
        pickup_h3_r7 = h3_indices[:pickup_h3_r7]
        drop_h3_r7 = h3_indices[:drop_h3_r7]

        # 1. Resolve route ONCE (same distance/duration for all vehicles)
        route_data = @route_resolver.resolve(
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          city_code: city_code,
          vehicle_type: 'multi'
        )

        # 1b. Validate route data — abort early if Google Maps failed
        if route_data.nil?
          return { error: 'Route resolution failed: no data returned', code: 502 }
        end
        if route_data[:error]
          return { error: "Route resolution failed: #{route_data[:error]}", code: 502 }
        end
        if route_data[:distance_m].nil? || route_data[:distance_m] <= 0
          return { error: 'Route resolution failed: invalid distance', code: 502 }
        end

        quotes = []
        errors = []

        # Shared zone resolver to avoid N+1 zone lookups across vehicles
        shared_resolver = ZonePricingResolver.new

        # 2a. Preload zone pricing for all vehicles to avoid N+1 in ZonePricingResolver
        # Without this, the first vehicle triggers lazy loading of ZoneVehiclePricing + time_pricings
        # per zone. By resolving zones and warming the resolver's cache here, we batch-load
        # all vehicle pricings for pickup/drop zones in 2-4 queries instead of ~80.
        begin
          h3_resolver = RoutePricing::Services::H3ZoneResolver.new(city_code)
          pickup_zone = h3_resolver.resolve(pickup_lat.to_f, pickup_lng.to_f)
          drop_zone = h3_resolver.resolve(drop_lat.to_f, drop_lng.to_f)

          if pickup_zone
            ZoneVehiclePricing.where(zone_id: pickup_zone.id, active: true)
                              .includes(:time_pricings)
                              .load
          end
          if drop_zone && drop_zone.id != pickup_zone&.id
            ZoneVehiclePricing.where(zone_id: drop_zone.id, active: true)
                              .includes(:time_pricings)
                              .load
          end
        rescue StandardError => e
          Rails.logger.debug("Multi-quote zone preload failed (non-fatal): #{e.message}")
        end

        # 2b. Batch preload all PricingConfigs (saves N queries)
        vehicle_types = ZoneConfigLoader::VEHICLE_TYPES
        configs_by_vehicle = PricingConfig
          .where(city_code: city_code.to_s.downcase, active: true, effective_until: nil)
          .where('effective_from <= ?', Time.current)
          .where(vehicle_type: vehicle_types)
          .order(version: :desc)
          .to_a
          .group_by(&:vehicle_type)
          .transform_values(&:first)

        # 3. Calculate price for each vehicle type
        vehicle_types.each do |vehicle_type|
          config = configs_by_vehicle[vehicle_type]
          unless config
            errors << { vehicle_type: vehicle_type, error: 'Config not found' }
            next
          end

          calculator = PriceCalculator.new(config: config, zone_resolver: shared_resolver)
          pricing_result = calculator.calculate(
            distance_m: route_data[:distance_m],
            duration_s: route_data[:duration_s],
            duration_in_traffic_s: route_data[:duration_in_traffic_s],
            pickup_lat: pickup_lat,
            pickup_lng: pickup_lng,
            drop_lat: drop_lat,
            drop_lng: drop_lng,
            item_value_paise: item_value_paise,
            quote_time: quote_time,
            weight_kg: weight_kg
          )

          pricing_version = "v#{config.version}"

          # Dynamic quote validity: higher surge = shorter validity window
          multi_combined_surge = pricing_result.dig(:breakdown, :combined_surge) || 1.0
          validity_minutes = case
                             when multi_combined_surge > 1.3 then 5
                             when multi_combined_surge > 1.1 then 8
                             else config.try(:quote_validity_minutes) || 15
                             end
          valid_until = Time.current + validity_minutes.minutes

          # Vendor payout prediction (two-sided pricing)
          vendor_prediction = predict_vendor_payout(
            city_code: city_code,
            vehicle_type: vehicle_type,
            distance_m: route_data[:distance_m],
            duration_in_traffic_s: route_data[:duration_in_traffic_s],
            time_band: pricing_result.dig(:breakdown, :zone_info, :time_band),
            pickup_lat: pickup_lat,
            pickup_lng: pickup_lng
          )
          vendor_attrs = build_vendor_quote_attrs(pricing_result[:final_price_paise], vendor_prediction)
          h3_attrs = build_h3_quote_attrs(pickup_h3_r8, drop_h3_r8, pickup_h3_r7, drop_h3_r7, pricing_result)

          quote = PricingQuote.create!(
            request_id: request_id,
            city_code: city_code,
            vehicle_type: vehicle_type,
            pickup_raw_lat: pickup_lat,
            pickup_raw_lng: pickup_lng,
            drop_raw_lat: drop_lat,
            drop_raw_lng: drop_lng,
            pickup_norm_lat: route_data[:pickup_norm][:lat],
            pickup_norm_lng: route_data[:pickup_norm][:lng],
            drop_norm_lat: route_data[:drop_norm][:lat],
            drop_norm_lng: route_data[:drop_norm][:lng],
            distance_m: route_data[:distance_m],
            duration_s: route_data[:duration_s],
            route_provider: route_data[:provider],
            route_cache_key: route_data[:cache_key],
            price_paise: pricing_result[:final_price_paise],
            price_confidence: route_data[:provider] == 'google' ? 'high' : 'estimated',
            pricing_version: pricing_version,
            breakdown_json: pricing_result[:breakdown],
            valid_until: valid_until,
            weight_kg: weight_kg,
            **vendor_attrs,
            **h3_attrs
          )

          quotes << {
            vehicle_type: vehicle_type,
            quote_id: quote.id,
            price_paise: quote.price_paise,
            price_inr: quote.price_inr,
            pricing_version: pricing_version,
            valid_until: valid_until.iso8601,
            expires_in_seconds: quote.remaining_seconds,
            breakdown: pricing_result[:breakdown]
          }
        rescue StandardError => e
          errors << { vehicle_type: vehicle_type, error: e.message }
          Rails.logger.error("MultiQuote error for #{vehicle_type}: #{e.message}")
        end

        result = {
          success: quotes.any?,
          code: 200,
          distance_m: route_data[:distance_m],
          duration_s: route_data[:duration_s],
          duration_in_traffic_s: route_data[:duration_in_traffic_s],
          provider: route_data[:provider],
          quotes: quotes,
          errors: errors.presence
        }

        # Add H3 context to multi-quote response if available
        if pickup_h3_r8 || drop_h3_r8
          result[:h3_context] = {
            pickup_hex: pickup_h3_r8,
            drop_hex: drop_h3_r8,
            resolution: 8
          }
        end

        result
      rescue StandardError => e
        Rails.logger.error("MultiQuote error: #{e.message}\n#{e.backtrace.join("\n")}")
        { error: e.message, code: 500 }
      end

      # Create linked outbound + return quotes with return trip discount.
      # Both quotes are created inside a transaction to prevent orphaned records.
      def create_round_trip_quote(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:,
                                  item_value_paise: nil, request_id: nil, quote_time: Time.current,
                                  return_quote_time: nil, weight_kg: nil)
        outbound = nil
        return_result = nil

        ActiveRecord::Base.transaction do
          # 1. Outbound quote (A -> B)
          outbound = create_quote(
            city_code: city_code,
            vehicle_type: vehicle_type,
            pickup_lat: pickup_lat,
            pickup_lng: pickup_lng,
            drop_lat: drop_lat,
            drop_lng: drop_lng,
            item_value_paise: item_value_paise,
            request_id: request_id,
            quote_time: quote_time,
            weight_kg: weight_kg
          )

          if outbound[:error]
            raise ActiveRecord::Rollback, outbound[:error]
          end

          # 2. Return quote (B -> A), default +2h if no return time specified
          return_time = return_quote_time || (quote_time + 2.hours)
          begin
            return_result = create_quote(
              city_code: city_code,
              vehicle_type: vehicle_type,
              pickup_lat: drop_lat,
              pickup_lng: drop_lng,
              drop_lat: pickup_lat,
              drop_lng: pickup_lng,
              item_value_paise: item_value_paise,
              request_id: request_id,
              quote_time: return_time,
              weight_kg: weight_kg
            )

            if return_result[:error]
              # Return quote failed — destroy the outbound quote to prevent orphans
              PricingQuote.find_by(id: outbound[:quote_id])&.destroy
              raise ActiveRecord::Rollback, return_result[:error]
            end
          rescue ActiveRecord::Rollback
            raise # re-raise Rollback so transaction rolls back
          rescue StandardError => e
            # Return quote raised an exception — clean up outbound quote
            PricingQuote.find_by(id: outbound[:quote_id])&.destroy
            raise e
          end

          # 3. Link quotes atomically
          outbound_quote = PricingQuote.find(outbound[:quote_id])
          return_quote = PricingQuote.find(return_result[:quote_id])
          outbound_quote.update!(linked_quote_id: return_quote.id, trip_leg: 'outbound')
          return_quote.update!(linked_quote_id: outbound_quote.id, trip_leg: 'return')
        end

        # Check if transaction rolled back
        return outbound if outbound&.dig(:error)
        return return_result if return_result&.dig(:error)
        return { error: 'Round trip quote creation failed', code: 500 } unless outbound && return_result

        # 4. Apply return trip discount to combined total
        config = PricingConfig.current_version(city_code, vehicle_type)
        discount_pct = config&.try(:return_trip_discount_pct).to_f
        discount_pct = 10.0 if discount_pct <= 0

        combined_paise = outbound[:price_paise] + return_result[:price_paise]
        discount_paise = (combined_paise * discount_pct / 100.0).round
        discounted_total = combined_paise - discount_paise

        {
          success: true,
          code: 200,
          outbound: outbound,
          return: return_result,
          round_trip_summary: {
            combined_price_paise: combined_paise,
            combined_price_inr: (combined_paise / 100.0).round(2),
            return_discount_pct: discount_pct,
            discount_paise: discount_paise,
            discounted_total_paise: discounted_total,
            discounted_total_inr: (discounted_total / 100.0).round(2),
            savings_inr: (discount_paise / 100.0).round(2)
          }
        }
      rescue StandardError => e
        Rails.logger.error("RoundTripQuote error: #{e.message}\n#{e.backtrace.join("\n")}")
        { error: e.message, code: 500 }
      end

      private

      # Predict vendor payout using VendorPayoutCalculator
      def predict_vendor_payout(city_code:, vehicle_type:, distance_m:, duration_in_traffic_s:, time_band:, pickup_lat:, pickup_lng:)
        return nil unless defined?(VendorRateCard) && VendorRateCard.table_exists?

        calculator = VendorPayoutCalculator.new(vendor_code: 'porter')
        calculator.calculate(
          city_code: city_code,
          vehicle_type: vehicle_type,
          distance_m: distance_m,
          duration_in_traffic_s: duration_in_traffic_s,
          time_band: time_band || RoutePricing::Services::TimeBandResolver.current_band,
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng
        )
      rescue StandardError => e
        Rails.logger.warn("Vendor prediction failed: #{e.message}")
        nil
      end

      # Compute H3 hex indices for pickup and drop points
      def compute_h3_indices(pickup_lat, pickup_lng, drop_lat, drop_lng)
        return {} unless defined?(H3)

        {
          pickup_h3_r8: (H3.from_geo_coordinates([pickup_lat.to_f, pickup_lng.to_f], 8).to_s(16) rescue nil),
          drop_h3_r8: (H3.from_geo_coordinates([drop_lat.to_f, drop_lng.to_f], 8).to_s(16) rescue nil),
          pickup_h3_r7: (H3.from_geo_coordinates([pickup_lat.to_f, pickup_lng.to_f], 7).to_s(16) rescue nil),
          drop_h3_r7: (H3.from_geo_coordinates([drop_lat.to_f, drop_lng.to_f], 7).to_s(16) rescue nil)
        }
      rescue StandardError => e
        Rails.logger.warn("H3 index computation failed: #{e.message}")
        {}
      end

      # Build H3-related attributes for PricingQuote.create!
      # Only includes columns that exist on the table (safe if migration hasn't run)
      def build_h3_quote_attrs(pickup_h3_r8, drop_h3_r8, pickup_h3_r7, drop_h3_r7, pricing_result)
        return {} unless PricingQuote.column_names.include?('pickup_h3_r8')

        h3_surge = pricing_result.dig(:breakdown, :h3_surge_multiplier) ||
                   pricing_result.dig(:breakdown, :combined_surge) ||
                   1.0

        {
          pickup_h3_r8: pickup_h3_r8,
          drop_h3_r8: drop_h3_r8,
          pickup_h3_r7: pickup_h3_r7,
          drop_h3_r7: drop_h3_r7,
          h3_surge_multiplier: h3_surge
        }
      end

      # Apply merchant pricing policies
      def apply_merchant_policies(merchant_id, base_price_paise, city_code:, vehicle_type:)
        return nil unless defined?(MerchantPricingPolicy) && MerchantPricingPolicy.table_exists?

        MerchantPricingPolicy.apply_policies(
          merchant_id, base_price_paise,
          city: city_code, vehicle: vehicle_type
        )
      rescue StandardError => e
        Rails.logger.warn("Merchant policy application failed: #{e.message}")
        nil
      end

      # Run shadow model scoring (non-blocking, failures are logged only)
      def run_shadow_model(quote, pricing_result, city_code, vehicle_type)
        return unless defined?(PricingModelConfig) && PricingModelConfig.table_exists?

        model_config = PricingModelConfig.active_model(city_code)
        return unless model_config

        zone_info = pricing_result.dig(:breakdown, :zone_info) || {}
        optimizer = CandidatePriceOptimizer.new(model_config: model_config)
        optimizer.score(
          quote_id: quote.id,
          deterministic_price_paise: quote.price_paise,
          city_code: city_code,
          vehicle_type: vehicle_type,
          time_band: zone_info[:time_band],
          pickup_zone: zone_info[:pickup_zone],
          drop_zone: zone_info[:drop_zone],
          distance_km: quote.distance_m ? quote.distance_m / 1000.0 : nil
        )
      rescue StandardError => e
        Rails.logger.warn("Shadow model scoring failed: #{e.message}")
      end

      # Build extra quote attributes for new pricing phases
      # Only includes columns that exist on the table (safe if migrations haven't run)
      def build_extra_quote_attrs(pricing_result, route_segments)
        attrs = {}
        breakdown = pricing_result[:breakdown] || {}

        if PricingQuote.column_names.include?('route_segments_json') && route_segments.present?
          attrs[:route_segments_json] = route_segments
        end

        if PricingQuote.column_names.include?('weather_condition')
          attrs[:weather_condition] = breakdown[:weather_condition]
        end

        if PricingQuote.column_names.include?('weather_multiplier')
          attrs[:weather_multiplier] = breakdown[:weather_multiplier] || 1.0
        end

        if PricingQuote.column_names.include?('backhaul_multiplier')
          attrs[:backhaul_multiplier] = breakdown[:backhaul_multiplier] || 1.0
        end

        if PricingQuote.column_names.include?('estimated_waiting_charge_paise')
          attrs[:estimated_waiting_charge_paise] = breakdown[:waiting_charge] || 0
        end

        if PricingQuote.column_names.include?('cancellation_risk_multiplier')
          attrs[:cancellation_risk_multiplier] = breakdown[:cancellation_risk_multiplier] || 1.0
        end

        attrs
      end

      # Track demand signal for H3 cell (fire-and-forget)
      def track_demand(city_code, pickup_h3_r7)
        return unless pickup_h3_r7.present?

        DemandTracker.new(city_code: city_code).record_quote(h3_r7: pickup_h3_r7)
      rescue StandardError => e
        Rails.logger.debug("Demand tracking failed: #{e.message}")
      end

      # Build vendor-related attributes for PricingQuote.create!
      def build_vendor_quote_attrs(final_price_paise, vendor_prediction)
        return {} unless vendor_prediction && vendor_prediction[:predicted_paise]

        predicted = vendor_prediction[:predicted_paise]
        margin = final_price_paise - predicted
        margin_pct = predicted > 0 ? ((margin.to_f / predicted) * 100).round(2) : 0

        {
          vendor_predicted_paise: predicted,
          vendor_code: vendor_prediction[:vendor_code],
          margin_paise: margin,
          margin_pct: margin_pct,
          vendor_confidence: vendor_prediction[:confidence]
        }
      end
    end
  end
end
