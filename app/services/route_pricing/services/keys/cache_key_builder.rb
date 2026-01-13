# frozen_string_literal: true

module RoutePricing
  module Services
    module Keys
      class CacheKeyBuilder
        def self.build_route_key(version: 'v1', city_code:, vehicle_type:, pickup_norm:, drop_norm:)
          new.build_route_key(
            version: version,
            city_code: city_code,
            vehicle_type: vehicle_type,
            pickup_norm: pickup_norm,
            drop_norm: drop_norm
          )
        end

        def build_route_key(version:, city_code:, vehicle_type:, pickup_norm:, drop_norm:)
          "route:#{version}:#{city_code}:#{vehicle_type}:#{pickup_norm[:lat]},#{pickup_norm[:lng]}:#{drop_norm[:lat]},#{drop_norm[:lng]}"
        end
      end
    end
  end
end
