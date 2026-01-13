# frozen_string_literal: true

module RoutePricing
  module Services
    class RouteResolver
      CACHE_TTL = 6.hours

      def initialize
        @normalizer = CoordinateNormalizer.new
        @provider = Providers::GoogleMapsProvider.new
        @cache_key_builder = Keys::CacheKeyBuilder.new
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

        # Cache miss - call provider
        route_data = @provider.get_route(
          pickup_lat: pickup_norm[:lat],
          pickup_lng: pickup_norm[:lng],
          drop_lat: drop_norm[:lat],
          drop_lng: drop_norm[:lng]
        )

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
    end
  end
end
