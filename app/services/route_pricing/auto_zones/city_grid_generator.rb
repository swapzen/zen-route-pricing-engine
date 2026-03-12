# frozen_string_literal: true

module RoutePricing
  module AutoZones
    class CityGridGenerator
      # Generates all R7 hexagons covering a city bounding box,
      # then filters out cells already assigned to manual zones.

      def initialize(boundary:, h3_resolution: 7, city_code:)
        @boundary = boundary
        @resolution = h3_resolution
        @city_code = city_code
      end

      # Returns Array of { h3_index_r7:, lat:, lng: } for unassigned cells
      def generate
        all_cells = cover_bbox
        assigned = assigned_h3_indexes
        unassigned = all_cells.reject { |cell| assigned.include?(cell[:h3_index_r7]) }

        Rails.logger.info "[CityGridGenerator] #{all_cells.size} total R7 cells, " \
                          "#{assigned.size} assigned, #{unassigned.size} unassigned"
        unassigned
      end

      private

      def cover_bbox
        lat_min = @boundary['lat_min'].to_f
        lat_max = @boundary['lat_max'].to_f
        lng_min = @boundary['lng_min'].to_f
        lng_max = @boundary['lng_max'].to_f

        # Use H3.polyfill for accurate hex coverage (no point sampling gaps)
        polygon = [[[lat_min, lng_min], [lat_min, lng_max], [lat_max, lng_max], [lat_max, lng_min]]]
        hex_integers = H3.polyfill(polygon, @resolution)

        cells = {}
        hex_integers.each do |h3_int|
          hex = h3_int.to_s(16)
          unless cells.key?(hex)
            center_lat, center_lng = H3.to_geo_coordinates(h3_int)
            cells[hex] = { h3_index_r7: hex, lat: center_lat, lng: center_lng }
          end
        end

        # Ensure corner hexes are included (polyfill may miss edge cells)
        corners = [
          [lat_min, lng_min], [lat_min, lng_max],
          [lat_max, lng_min], [lat_max, lng_max]
        ]
        corners.each do |clat, clng|
          h3_int = H3.from_geo_coordinates([clat, clng], @resolution)
          hex = h3_int.to_s(16)
          unless cells.key?(hex)
            center_lat, center_lng = H3.to_geo_coordinates(h3_int)
            cells[hex] = { h3_index_r7: hex, lat: center_lat, lng: center_lng }
          end
        end

        cells.values
      end

      def assigned_h3_indexes
        ZoneH3Mapping.for_city(@city_code)
                     .joins(:zone)
                     .where(zones: { auto_generated: false })
                     .distinct
                     .pluck(:h3_index_r7)
                     .to_set
      end
    end
  end
end
