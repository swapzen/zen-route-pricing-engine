# frozen_string_literal: true

module RoutePricing
  module Services
    class H3SurgeResolver
      RESOLUTION = 9
      CACHE_TTL = 5.minutes  # Surge data is time-sensitive
      DEFAULT_MULTIPLIER = 1.0
      MAX_MULTIPLIER = 3.0

      def initialize(city_code)
        @city_code = city_code.to_s.downcase
      end

      # Returns surge multiplier for a given lat/lng point
      # Uses Res 9 hex for hyperlocal granularity
      def resolve(lat, lng, time_band: nil)
        return DEFAULT_MULTIPLIER unless surge_available?

        h3_r9 = H3.from_geo_coordinates([lat.to_f, lng.to_f], RESOLUTION).to_s(16)

        # Check cache first
        cache_key = "surge:#{@city_code}:#{h3_r9}:#{time_band || 'all'}"
        cached = Rails.cache.read(cache_key)
        return cached.to_f if cached

        # DB lookup
        bucket = H3SurgeBucket.find_surge(h3_r9, @city_code, time_band)
        multiplier = bucket&.surge_multiplier || DEFAULT_MULTIPLIER
        multiplier = [multiplier, MAX_MULTIPLIER].min  # Safety cap

        Rails.cache.write(cache_key, multiplier, expires_in: CACHE_TTL)
        multiplier
      rescue StandardError => e
        Rails.logger.debug("H3SurgeResolver error: #{e.message}")
        DEFAULT_MULTIPLIER
      end

      # Batch resolve for multiple points (useful for heatmap)
      def resolve_area(center_lat, center_lng, k_ring_size: 2, time_band: nil)
        center_hex = H3.from_geo_coordinates([center_lat.to_f, center_lng.to_f], RESOLUTION)
        hexes = H3.k_ring(center_hex, k_ring_size)

        hex_strings = hexes.map { |h| h.to_s(16) }
        buckets = H3SurgeBucket.for_city(@city_code)
                               .where(h3_index: hex_strings)
                               .active
                               .for_time_band(time_band)
                               .index_by(&:h3_index)

        hexes.map do |h|
          hex_str = h.to_s(16)
          lat, lng = H3.to_geo_coordinates(h)
          bucket = buckets[hex_str]
          {
            h3_index: hex_str,
            lat: lat.round(6),
            lng: lng.round(6),
            surge_multiplier: bucket&.surge_multiplier || DEFAULT_MULTIPLIER,
            demand_score: bucket&.demand_score || 0.0,
            supply_score: bucket&.supply_score || 0.0
          }
        end
      end

      # Get city-wide surge summary
      def city_surge_summary(time_band: nil)
        scope = H3SurgeBucket.for_city(@city_code).active
        scope = scope.for_time_band(time_band) if time_band

        {
          total_hexes: scope.count,
          surging_hexes: scope.surging.count,
          avg_multiplier: scope.average(:surge_multiplier)&.round(2) || 1.0,
          max_multiplier: scope.maximum(:surge_multiplier) || 1.0,
          avg_demand: scope.average(:demand_score)&.round(1) || 0.0,
          avg_supply: scope.average(:supply_score)&.round(1) || 0.0
        }
      end

      private

      def surge_available?
        defined?(H3) && defined?(H3SurgeBucket) && H3SurgeBucket.table_exists?
      rescue StandardError
        false
      end
    end
  end
end
