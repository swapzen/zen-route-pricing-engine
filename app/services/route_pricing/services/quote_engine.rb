# frozen_string_literal: true

module RoutePricing
  module Services
    class QuoteEngine
      # Allow injecting a mock resolver for testing
      def initialize(route_resolver: RouteResolver.new)
        @route_resolver = route_resolver
      end

      def create_quote(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, item_value_paise: nil, request_id: nil, quote_time: Time.current, weight_kg: nil)
        # 1. Fetch current config
        config = PricingConfig.current_version(city_code, vehicle_type)
        return { error: 'Config not found for city/vehicle combination', code: 404 } unless config

        # 2. Resolve route
        route_data = @route_resolver.resolve(
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          city_code: city_code,
          vehicle_type: vehicle_type
        )

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
          weight_kg: weight_kg
        )
        pricing_version = "v#{config.version}"
        validity_minutes = config.try(:quote_validity_minutes) || 10
        valid_until = Time.current + validity_minutes.minutes

        # 4. Persist quote
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
          scheduled_for: quote_time > Time.current ? quote_time : nil
        )

        # 5. Return formatted response
        {
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
      rescue StandardError => e
        Rails.logger.error("QuoteEngine error: #{e.message}\n#{e.backtrace.join("\n")}")
        { error: e.message, code: 500 }
      end

      # Create quotes for all vehicle types with a single route resolution
      def create_multi_quote(city_code:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, item_value_paise: nil, request_id: nil, quote_time: Time.current, weight_kg: nil)
        # 1. Resolve route ONCE (same distance/duration for all vehicles)
        route_data = @route_resolver.resolve(
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          city_code: city_code,
          vehicle_type: 'multi'
        )

        quotes = []
        errors = []

        # 2. Calculate price for each vehicle type
        ZoneConfigLoader::VEHICLE_TYPES.each do |vehicle_type|
          config = PricingConfig.current_version(city_code, vehicle_type)
          unless config
            errors << { vehicle_type: vehicle_type, error: 'Config not found' }
            next
          end

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
            weight_kg: weight_kg
          )

          pricing_version = "v#{config.version}"
          validity_minutes = config.try(:quote_validity_minutes) || 10
          valid_until = Time.current + validity_minutes.minutes

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
            weight_kg: weight_kg
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

        {
          success: quotes.any?,
          code: 200,
          distance_m: route_data[:distance_m],
          duration_s: route_data[:duration_s],
          duration_in_traffic_s: route_data[:duration_in_traffic_s],
          provider: route_data[:provider],
          quotes: quotes,
          errors: errors.presence
        }
      rescue StandardError => e
        Rails.logger.error("MultiQuote error: #{e.message}\n#{e.backtrace.join("\n")}")
        { error: e.message, code: 500 }
      end

      # Create linked outbound + return quotes with return trip discount
      def create_round_trip_quote(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:,
                                  item_value_paise: nil, request_id: nil, quote_time: Time.current,
                                  return_quote_time: nil, weight_kg: nil)
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
        return outbound if outbound[:error]

        # 2. Return quote (B -> A), default +2h if no return time specified
        return_time = return_quote_time || (quote_time + 2.hours)
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
        return return_result if return_result[:error]

        # 3. Apply return trip discount to combined total
        config = PricingConfig.current_version(city_code, vehicle_type)
        discount_pct = config&.try(:return_trip_discount_pct).to_f
        discount_pct = 10.0 if discount_pct <= 0

        combined_paise = outbound[:price_paise] + return_result[:price_paise]
        discount_paise = (combined_paise * discount_pct / 100.0).round
        discounted_total = combined_paise - discount_paise

        # 4. Link quotes
        outbound_quote = PricingQuote.find(outbound[:quote_id])
        return_quote = PricingQuote.find(return_result[:quote_id])
        outbound_quote.update!(linked_quote_id: return_quote.id, trip_leg: 'outbound')
        return_quote.update!(linked_quote_id: outbound_quote.id, trip_leg: 'return')

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
    end
  end
end
