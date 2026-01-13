# frozen_string_literal: true

module RoutePricing
  module Services
    class QuoteEngine
      # Allow injecting a mock resolver for testing
      def initialize(route_resolver: RouteResolver.new)
        @route_resolver = route_resolver
      end

      def create_quote(city_code:, vehicle_type:, pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, item_value_paise: nil, request_id: nil)
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

        # 3. Calculate price
        calculator = PriceCalculator.new(config: config)
        pricing_result = calculator.calculate(
          distance_m: route_data[:distance_m],
          duration_s: route_data[:duration_s],  # Pass resolver's duration
          duration_in_traffic_s: route_data[:duration_in_traffic_s],
          item_value_paise: item_value_paise,
          quote_time: Time.current
        )

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
          pricing_version: 'v1',
          breakdown_json: pricing_result[:breakdown]
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
          pricing_version: 'v1',
          confidence: quote.price_confidence,
          provider: route_data[:provider],
          breakdown: pricing_result[:breakdown]
        }
      rescue StandardError => e
        Rails.logger.error("QuoteEngine error: #{e.message}\n#{e.backtrace.join("\n")}")
        { error: e.message, code: 500 }
      end
    end
  end
end
