# frozen_string_literal: true

module RoutePricing
  module Services
    module Keys
      class CacheKeyBuilder
        def self.build_route_key(version: 'v1', city_code:, vehicle_type:, pickup_norm:, drop_norm:, time_bucket: nil)
          new.build_route_key(
            version: version,
            city_code: city_code,
            vehicle_type: vehicle_type,
            pickup_norm: pickup_norm,
            drop_norm: drop_norm,
            time_bucket: time_bucket
          )
        end

        # Include a 2-hour time bucket in the cache key so that traffic data
        # (duration_in_traffic_s) stays reasonably fresh. Without this, a route
        # cached at 10 AM would serve stale traffic data at 6 PM.
        def build_route_key(version:, city_code:, vehicle_type:, pickup_norm:, drop_norm:, time_bucket: nil)
          bucket = time_bucket || (Time.current.hour / 2)
          "route:#{version}:#{city_code}:#{vehicle_type}:" \
            "#{pickup_norm[:lat]},#{pickup_norm[:lng]}:" \
            "#{drop_norm[:lat]},#{drop_norm[:lng]}:" \
            "t#{bucket}"
        end
      end
    end
  end
end
