# frozen_string_literal: true

require 'net/http'
require 'json'

module RoutePricing
  module Services
    module Providers
      class GoogleMapsProvider
        CACHE_TTL = 6.hours
        TORTUOSITY_FACTOR = 1.4
        AVERAGE_SPEED_KMH = 25

        def initialize
          @api_key = ENV['GOOGLE_MAPS_API_KEY']
        end

        def get_route(pickup_lat:, pickup_lng:, drop_lat:, drop_lng:)
          # Check environment strategy
          strategy = ENV['ROUTE_PROVIDER_STRATEGY'] || 'google'
          
          if strategy == 'local' || strategy == 'haversine'
            return haversine_fallback(pickup_lat, pickup_lng, drop_lat, drop_lng)
          end

          # Call Google Maps Distance Matrix API
          begin
            response = call_google_api(pickup_lat, pickup_lng, drop_lat, drop_lng)
            parse_google_response(response)
          rescue StandardError => e
            Rails.logger.warn("Google Maps API failed: #{e.message}. Falling back to Haversine.")
            haversine_fallback(pickup_lat, pickup_lng, drop_lat, drop_lng)
          end
        end

        private

        def call_google_api(pickup_lat, pickup_lng, drop_lat, drop_lng)
          uri = URI('https://maps.googleapis.com/maps/api/distancematrix/json')
          params = {
            origins: "#{pickup_lat},#{pickup_lng}",
            destinations: "#{drop_lat},#{drop_lng}",
            departure_time: 'now',
            traffic_model: 'best_guess',
            key: @api_key
          }
          uri.query = URI.encode_www_form(params)

          # Configure HTTP with SSL settings
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 10
          http.read_timeout = 10
          
          # Fix SSL certificate verification issues in development
          # TODO: Use proper CA certificates in production
          if Rails.env.development? || Rails.env.test?
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          else
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          request = Net::HTTP::Get.new(uri)
          response = http.request(request)
          
          raise "API request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end

        def parse_google_response(response)
          if response['status'] != 'OK'
            raise "API returned status: #{response['status']}"
          end

          element = response.dig('rows', 0, 'elements', 0)
          raise "No route data found" if element.nil? || element['status'] != 'OK'

          distance_m = element.dig('distance', 'value')
          duration_s = element.dig('duration', 'value')
          duration_in_traffic_s = element.dig('duration_in_traffic', 'value')

          {
            distance_m: distance_m,
            duration_s: duration_s,
            duration_in_traffic_s: duration_in_traffic_s,
            traffic_model: 'best_guess',
            provider: 'google'
          }
        end

        def haversine_fallback(pickup_lat, pickup_lng, drop_lat, drop_lng)
          air_distance_m = haversine_distance(pickup_lat, pickup_lng, drop_lat, drop_lng)
          
          # Apply tortuosity factor
          road_distance_m = (air_distance_m * TORTUOSITY_FACTOR).round

          # Estimate duration using average speed
          duration_s = ((road_distance_m / 1000.0) / AVERAGE_SPEED_KMH * 3600).round

          {
            distance_m: road_distance_m,
            duration_s: duration_s,
            duration_in_traffic_s: nil,
            traffic_model: 'haversine',
            provider: 'haversine_fallback'
          }
        end

        def haversine_distance(lat1, lon1, lat2, lon2)
          earth_radius_m = 6371000 # meters

          dlat = deg_to_rad(lat2 - lat1)
          dlon = deg_to_rad(lon2 - lon1)

          a = Math.sin(dlat / 2) ** 2 +
              Math.cos(deg_to_rad(lat1)) * Math.cos(deg_to_rad(lat2)) *
              Math.sin(dlon / 2) ** 2

          c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

          (earth_radius_m * c).round
        end

        def deg_to_rad(degrees)
          degrees * Math::PI / 180
        end
      end
    end
  end
end
