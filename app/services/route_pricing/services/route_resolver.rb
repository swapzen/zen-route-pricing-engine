# frozen_string_literal: true

require 'timeout'

module RoutePricing
  module Services
    class RouteResolver
      CACHE_TTL = 2.hours  # Reduced from 6h to keep traffic data fresh (matches 2h time bucket in cache key)
      PROVIDER_TIMEOUT = 15  # Defense-in-depth: max seconds for provider call (HTTP timeouts are 10s each)

      def initialize(route_resolver: nil)
        @normalizer = CoordinateNormalizer.new
        @provider = Providers::GoogleMapsProvider.new
        @cache_key_builder = Keys::CacheKeyBuilder.new
        @circuit_breaker = CircuitBreaker.new(
          service: 'google_maps',
          threshold: 3,
          timeout: 120,
          window: 300
        )
      end

      # Resolve route with step-by-step directions for segment pricing
      # Falls back to standard resolve (Distance Matrix) if Directions fails
      def resolve_with_segments(pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, city_code:, vehicle_type:)
        pickup_norm = @normalizer.normalize(pickup_lat, pickup_lng)
        drop_norm = @normalizer.normalize(drop_lat, drop_lng)

        cache_key = @cache_key_builder.build_route_key(
          version: 'rs',
          city_code: city_code,
          vehicle_type: vehicle_type,
          pickup_norm: pickup_norm,
          drop_norm: drop_norm
        )

        cached_data = Rails.cache.read(cache_key)
        if cached_data
          result = cached_data.is_a?(String) ? JSON.parse(cached_data, symbolize_names: true) : cached_data
          result[:cache_hit] = true
          return result.merge(pickup_norm: pickup_norm, drop_norm: drop_norm, cache_key: cache_key)
        end

        route_data = call_provider_with_breaker(city_code) do
          @provider.get_directions(
            pickup_lat: pickup_norm[:lat],
            pickup_lng: pickup_norm[:lng],
            drop_lat: drop_norm[:lat],
            drop_lng: drop_norm[:lng]
          )
        end

        Rails.cache.write(cache_key, route_data, expires_in: CACHE_TTL)

        route_data.merge(
          pickup_norm: pickup_norm,
          drop_norm: drop_norm,
          cache_key: cache_key,
          cache_hit: false
        )
      rescue StandardError => e
        Rails.logger.warn("resolve_with_segments failed: #{e.message}. Falling back to resolve.")
        resolve(
          pickup_lat: pickup_lat,
          pickup_lng: pickup_lng,
          drop_lat: drop_lat,
          drop_lng: drop_lng,
          city_code: city_code,
          vehicle_type: vehicle_type
        )
      end

      def resolve(pickup_lat:, pickup_lng:, drop_lat:, drop_lng:, city_code:, vehicle_type:)
        # Normalize coordinates
        pickup_norm = @normalizer.normalize(pickup_lat, pickup_lng)
        drop_norm = @normalizer.normalize(drop_lat, drop_lng)

        # Build cache key
        cache_key = @cache_key_builder.build_route_key(
          version: 'v1',
          city_code: city_code,
          vehicle_type: vehicle_type,
          pickup_norm: pickup_norm,
          drop_norm: drop_norm
        )

        # Try cache first using Rails.cache (connection pool)
        cached_data = Rails.cache.read(cache_key)
        if cached_data
          result = cached_data.is_a?(String) ? JSON.parse(cached_data, symbolize_names: true) : cached_data
          result[:cache_hit] = true
          return result.merge(
            pickup_norm: pickup_norm,
            drop_norm: drop_norm,
            cache_key: cache_key
          )
        end

        # Cache miss - call provider with circuit breaker + timeout guard
        # Falls back to haversine distance estimate if provider/circuit fails
        route_data = begin
          call_provider_with_breaker(city_code) do
            @provider.get_route(
              pickup_lat: pickup_norm[:lat],
              pickup_lng: pickup_norm[:lng],
              drop_lat: drop_norm[:lat],
              drop_lng: drop_norm[:lng]
            )
          end
        rescue StandardError => e
          Rails.logger.warn("[ROUTE_FALLBACK] Provider failed (#{e.message}), using haversine estimate")
          haversine_fallback(pickup_norm[:lat], pickup_norm[:lng], drop_norm[:lat], drop_norm[:lng])
        end

        # Cache result using Rails.cache (handles connection pooling)
        Rails.cache.write(cache_key, route_data, expires_in: CACHE_TTL)

        # Return with normalized coords and cache key
        route_data.merge(
          pickup_norm: pickup_norm,
          drop_norm: drop_norm,
          cache_key: cache_key,
          cache_hit: false
        )
      end

      # Expose circuit breaker stats for admin health endpoint
      def provider_health
        @circuit_breaker.stats
      end

      private

      # Haversine distance estimate when Google Maps is unavailable.
      # Applies 1.3x road factor (straight-line → actual driving distance in Indian cities).
      def haversine_fallback(lat1, lng1, lat2, lng2)
        r = 6_371_000 # Earth radius meters
        dlat = (lat2 - lat1) * Math::PI / 180
        dlng = (lng2 - lng1) * Math::PI / 180
        a = Math.sin(dlat / 2)**2 +
            Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) *
            Math.sin(dlng / 2)**2
        straight_line_m = 2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        road_distance_m = (straight_line_m * 1.3).round  # 30% road factor
        estimated_duration_s = (road_distance_m / 8.33).round  # ~30 km/h avg speed

        {
          distance_m: road_distance_m,
          duration_s: estimated_duration_s,
          duration_in_traffic_s: (estimated_duration_s * 1.2).round,  # 20% traffic buffer
          provider: 'haversine_fallback'
        }
      end

      def call_provider_with_breaker(_city_code)
        Timeout.timeout(PROVIDER_TIMEOUT) do
          @circuit_breaker.call { yield }
        end
      rescue CircuitBreaker::CircuitOpenError => e
        Rails.logger.warn("[CIRCUIT_OPEN] #{e.message}. Propagating to trigger haversine fallback.")
        raise StandardError, "Circuit open: #{e.message}"
      end
    end
  end
end
