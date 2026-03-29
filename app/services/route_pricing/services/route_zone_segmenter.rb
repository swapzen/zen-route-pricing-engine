# frozen_string_literal: true

module RoutePricing
  module Services
    # Segments a route into zone-based segments for per-zone pricing
    class RouteZoneSegmenter
      Segment = Struct.new(:zone, :distance_m, :start_point, :end_point, keyword_init: true)

      def initialize(city_code:)
        @city_code = city_code
        @h3_resolver = H3ZoneResolver.new(city_code)
      end

      # Takes steps from Google Directions API
      # Returns [Segment, Segment, ...] with consecutive same-zone steps merged
      def segment_route(steps:)
        return [] if steps.blank?

        segments = []
        current_zone_code = nil
        current_distance = 0
        current_start = nil

        steps.each do |step|
          # Resolve zone at midpoint of step
          mid_lat = ((step[:start_lat] || step['start_lat']).to_f + (step[:end_lat] || step['end_lat']).to_f) / 2.0
          mid_lng = ((step[:start_lng] || step['start_lng']).to_f + (step[:end_lng] || step['end_lng']).to_f) / 2.0
          step_distance = (step[:distance_m] || step['distance_m']).to_f

          zone = @h3_resolver.resolve(mid_lat, mid_lng)
          zone_code = zone&.zone_code || 'unknown'

          step_start = { lat: (step[:start_lat] || step['start_lat']).to_f,
                         lng: (step[:start_lng] || step['start_lng']).to_f }
          step_end = { lat: (step[:end_lat] || step['end_lat']).to_f,
                       lng: (step[:end_lng] || step['end_lng']).to_f }

          if zone_code == current_zone_code
            # Same zone — accumulate distance
            current_distance += step_distance
          else
            # Zone changed — flush previous segment
            if current_zone_code
              segments << Segment.new(
                zone: current_zone_code,
                distance_m: current_distance.round,
                start_point: current_start,
                end_point: step_start
              )
            end

            # Start new segment
            current_zone_code = zone_code
            current_distance = step_distance
            current_start = step_start
          end
        end

        # Flush last segment
        if current_zone_code && current_distance > 0
          last_step = steps.last
          last_end = { lat: (last_step[:end_lat] || last_step['end_lat']).to_f,
                       lng: (last_step[:end_lng] || last_step['end_lng']).to_f }
          segments << Segment.new(
            zone: current_zone_code,
            distance_m: current_distance.round,
            start_point: current_start,
            end_point: last_end
          )
        end

        segments
      rescue StandardError => e
        Rails.logger.warn("RouteZoneSegmenter error: #{e.message}")
        []
      end
    end
  end
end
