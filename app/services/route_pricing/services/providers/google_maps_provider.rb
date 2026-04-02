# frozen_string_literal: true

require 'net/http'
require 'json'

module RoutePricing
  module Services
    module Providers
      class GoogleMapsProvider
        CACHE_TTL = 6.hours
        TORTUOSITY_FACTOR = 1.4  # default fallback
        AVERAGE_SPEED_KMH = 25

        # Per-city tortuosity factors for haversine fallback
        # Based on road network density analysis
        CITY_TORTUOSITY = {
          'hyd' => 1.35,
          'blr' => 1.42,
          'mum' => 1.50,
          'del' => 1.38,
          'che' => 1.40,
          'pun' => 1.38
        }.freeze

        def initialize
          @api_key = ENV['GOOGLE_MAPS_API_KEY']
        end

        # Google Directions API — returns step-by-step route with per-step distances
        # Used for route-segment pricing (Phase 1)
        def get_directions(pickup_lat:, pickup_lng:, drop_lat:, drop_lng:)
          strategy = ENV['ROUTE_PROVIDER_STRATEGY'] || 'google'

          if strategy == 'local' || strategy == 'haversine'
            return haversine_fallback(pickup_lat, pickup_lng, drop_lat, drop_lng)
          end

          begin
            response = call_directions_api(pickup_lat, pickup_lng, drop_lat, drop_lng)
            parse_directions_response(response)
          rescue StandardError => e
            Rails.logger.warn("Google Directions API failed: #{e.message}. Falling back to Haversine.")
            haversine_fallback(pickup_lat, pickup_lng, drop_lat, drop_lng)
          end
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
          
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER

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

        def call_directions_api(pickup_lat, pickup_lng, drop_lat, drop_lng)
          uri = URI('https://maps.googleapis.com/maps/api/directions/json')
          params = {
            origin: "#{pickup_lat},#{pickup_lng}",
            destination: "#{drop_lat},#{drop_lng}",
            departure_time: 'now',
            traffic_model: 'best_guess',
            key: @api_key
          }
          uri.query = URI.encode_www_form(params)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 10
          http.read_timeout = 10

          http.verify_mode = OpenSSL::SSL::VERIFY_PEER

          request = Net::HTTP::Get.new(uri)
          response = http.request(request)

          raise "Directions API request failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end

        def parse_directions_response(response)
          raise "Directions API returned status: #{response['status']}" if response['status'] != 'OK'

          route = response.dig('routes', 0)
          raise "No route found" unless route

          leg = route.dig('legs', 0)
          raise "No leg found" unless leg

          distance_m = leg.dig('distance', 'value')
          duration_s = leg.dig('duration', 'value')
          duration_in_traffic_s = leg.dig('duration_in_traffic', 'value')

          steps = (leg['steps'] || []).map do |step|
            {
              start_lat: step.dig('start_location', 'lat'),
              start_lng: step.dig('start_location', 'lng'),
              end_lat: step.dig('end_location', 'lat'),
              end_lng: step.dig('end_location', 'lng'),
              distance_m: step.dig('distance', 'value'),
              duration_s: step.dig('duration', 'value')
            }
          end

          {
            distance_m: distance_m,
            duration_s: duration_s,
            duration_in_traffic_s: duration_in_traffic_s,
            traffic_model: 'best_guess',
            provider: 'google',
            steps: steps
          }
        end

        def haversine_fallback(pickup_lat, pickup_lng, drop_lat, drop_lng, city_code: nil)
          air_distance_m = haversine_distance(pickup_lat, pickup_lng, drop_lat, drop_lng)

          # Apply per-city tortuosity factor (or default)
          factor = city_code ? CITY_TORTUOSITY.fetch(city_code.to_s, TORTUOSITY_FACTOR) : TORTUOSITY_FACTOR
          road_distance_m = (air_distance_m * factor).round

          # Estimate duration using average speed
          duration_s = ((road_distance_m / 1000.0) / AVERAGE_SPEED_KMH * 3600).round

          {
            distance_m: road_distance_m,
            duration_s: duration_s,
            duration_in_traffic_s: nil,
            traffic_model: 'haversine',
            provider: 'haversine_fallback',
            fallback_reason: 'provider_unavailable'
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
