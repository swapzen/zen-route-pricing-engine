# frozen_string_literal: true

module RoutePricing
  module Services
    class VendorPayoutCalculator
      DEFAULT_VENDOR = 'porter'

      def initialize(vendor_code: DEFAULT_VENDOR)
        @vendor_code = vendor_code
      end

      def calculate(city_code:, vehicle_type:, distance_m:, duration_in_traffic_s:, time_band:, pickup_lat: nil, pickup_lng: nil)
        rate_card = VendorRateCard.current_rate(@vendor_code, city_code, vehicle_type, time_band: time_band)
        return no_rate_card_result unless rate_card

        # Base fare
        base = rate_card.base_fare_paise

        # Per-km component (distance beyond free_km)
        free_m = rate_card.free_km_m || 1000
        chargeable_m = [0, distance_m - free_m].max
        per_km_component = (chargeable_m / 1000.0) * rate_card.per_km_rate_paise

        # Per-minute component
        per_min_component = if rate_card.per_min_rate_paise > 0 && duration_in_traffic_s.to_i > 0
                              (duration_in_traffic_s / 60.0) * rate_card.per_min_rate_paise
                            else
                              0
                            end

        # Dead-km component (simplified: flat rate, no H3 lookup for vendor prediction)
        dead_km_component = 0 # Reserved for future vendor dead-km modeling

        predicted = base + per_km_component + per_min_component + dead_km_component

        # Apply min fare floor
        predicted = [predicted, rate_card.min_fare_paise].max

        # Round to integer paise
        predicted_paise = predicted.round

        # Confidence based on recent actuals count
        confidence = compute_confidence(city_code, vehicle_type)

        {
          predicted_paise: predicted_paise,
          confidence: confidence,
          vendor_code: @vendor_code,
          breakdown: {
            base_fare_paise: base,
            per_km_component: per_km_component.round,
            per_min_component: per_min_component.round,
            dead_km_component: dead_km_component,
            min_fare_paise: rate_card.min_fare_paise,
            chargeable_m: chargeable_m.round,
            free_km_m: free_m,
            rate_card_version: rate_card.version
          }
        }
      end

      private

      def no_rate_card_result
        {
          predicted_paise: nil,
          confidence: 'none',
          vendor_code: @vendor_code,
          breakdown: {}
        }
      end

      def compute_confidence(city_code, vehicle_type)
        count = PricingActual
          .joins(:pricing_quote)
          .where(pricing_quotes: { city_code: city_code, vehicle_type: vehicle_type })
          .where(vendor: @vendor_code)
          .where('pricing_actuals.created_at > ?', 30.days.ago)
          .count

        case count
        when 0..2 then 'low'
        when 3..20 then 'medium'
        else 'high'
        end
      rescue StandardError => e
        Rails.logger.warn("VendorPayoutCalculator confidence check failed: #{e.message}")
        'low'
      end
    end
  end
end
