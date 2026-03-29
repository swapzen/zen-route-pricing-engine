# frozen_string_literal: true

module RoutePricing
  module Services
    class ZoneOverlapDetector
      # Detects H3 cells claimed by multiple zones and reports conflicts
      # Also detects H3 vs BBox resolution mismatches for given coordinates

      def initialize(city_code)
        @city_code = city_code
      end

      # Returns array of { h3_hex:, zones: [{ zone_code:, priority:, zone_type: }] }
      def find_overlapping_cells
        overlapping_hexes = ZoneH3Mapping.where(city_code: @city_code)
          .group(:h3_index_r7)
          .having('COUNT(DISTINCT zone_id) > 1')
          .pluck(:h3_index_r7)

        overlapping_hexes.map do |h3_hex|
          mappings = ZoneH3Mapping.where(h3_index_r7: h3_hex, city_code: @city_code)
            .includes(:zone)
          {
            h3_hex: h3_hex,
            zones: mappings.map do |m|
              {
                zone_code: m.zone.zone_code,
                priority: m.zone.priority,
                zone_type: m.zone.zone_type,
                zone_id: m.zone.id
              }
            end
          }
        end
      end

      # Detects where H3 and BBox resolve differently for a given point
      def detect_conflict(lat, lng)
        h3_resolver = H3ZoneResolver.new(@city_code)
        h3_zone = h3_resolver.resolve(lat, lng)

        bbox_zone = Zone.where(city: @city_code, status: true)
          .order(priority: :desc, zone_code: :asc)
          .detect { |z| z.lat_min && lat >= z.lat_min && lat <= z.lat_max && lng >= z.lng_min && lng <= z.lng_max }

        conflict = h3_zone && bbox_zone && h3_zone.id != bbox_zone.id

        {
          lat: lat,
          lng: lng,
          h3_zone: h3_zone&.zone_code,
          bbox_zone: bbox_zone&.zone_code,
          conflict: conflict,
          h3_priority: h3_zone&.priority,
          bbox_priority: bbox_zone&.priority
        }
      end

      # Returns summary stats
      def summary
        overlaps = find_overlapping_cells
        total_cells = ZoneH3Mapping.where(city_code: @city_code).distinct.count(:h3_index_r7)

        {
          city_code: @city_code,
          total_r7_cells: total_cells,
          overlapping_cells: overlaps.size,
          overlap_pct: (overlaps.size.to_f / total_cells * 100).round(1),
          max_zones_per_cell: overlaps.map { |o| o[:zones].size }.max || 0,
          worst_cells: overlaps.sort_by { |o| -o[:zones].size }.first(5)
        }
      end
    end
  end
end
