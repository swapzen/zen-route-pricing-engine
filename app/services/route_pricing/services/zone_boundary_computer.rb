# frozen_string_literal: true

module RoutePricing
  module Services
    class ZoneBoundaryComputer
      # Computes zone boundary polygons from H3 cells using edge-counting.
      #
      # Algorithm (O(N) per zone where N = number of hex cells):
      # 1. For each R7 cell → H3.to_boundary → 6 vertices → 6 edges
      # 2. Count each edge (canonical sorted vertex pair).
      #    Edges appearing once = boundary. Twice = interior (shared).
      # 3. Chain boundary edges into closed polygon ring(s)
      # 4. Store as GeoJSON Polygon or MultiPolygon (disconnected regions)
      # 5. Fallback: zones without H3 → bbox rectangle as GeoJSON

      # Rounding precision for vertex deduplication (6 decimal places ≈ 0.11m)
      PRECISION = 6

      def initialize(zone)
        @zone = zone
      end

      def compute!
        h3_mappings = ZoneH3Mapping.where(zone_id: @zone.id).pluck(:h3_index_r7)

        if h3_mappings.any?
          geojson = compute_from_h3(h3_mappings)
          centroid = compute_centroid_from_h3(h3_mappings)
        elsif @zone.lat_min && @zone.lat_max && @zone.lng_min && @zone.lng_max
          geojson = compute_from_bbox
          centroid = bbox_centroid
        else
          return nil
        end

        @zone.update!(
          boundary_geojson: geojson,
          center_lat: centroid[:lat],
          center_lng: centroid[:lng]
        )

        geojson
      end

      def self.compute_for_city!(city_code)
        zones = Zone.for_city(city_code).active
        computed = 0
        errors = 0

        zones.find_each do |zone|
          new(zone).compute!
          computed += 1
        rescue StandardError => e
          errors += 1
          Rails.logger.error "[ZoneBoundaryComputer] Failed for zone #{zone.zone_code}: #{e.message}"
        end

        Rails.logger.info "[ZoneBoundaryComputer] Computed boundaries for #{computed} zones in #{city_code} (#{errors} errors)"
        { computed: computed, errors: errors }
      end

      private

      def compute_from_h3(h3_indexes)
        # Render each H3 cell as its own polygon — exact boundaries, no inflation.
        # Only actual zone coverage is colored.
        cell_rings = []

        h3_indexes.each do |h3_hex|
          h3_int = h3_hex.to_i(16)
          vertices = H3.to_boundary(h3_int)

          ring = vertices.map { |v| [v[1].round(PRECISION), v[0].round(PRECISION)] }
          ring << ring.first unless ring.first == ring.last
          cell_rings << ring
        end

        return compute_from_bbox if cell_rings.empty?

        if cell_rings.size == 1
          { type: 'Polygon', coordinates: [cell_rings.first] }
        else
          { type: 'MultiPolygon', coordinates: cell_rings.map { |ring| [ring] } }
        end
      end

      def chain_edges_into_rings(edges)
        # Build adjacency: vertex → list of connected vertices
        adjacency = Hash.new { |h, k| h[k] = [] }
        edges.each do |v1, v2|
          adjacency[v1] << v2
          adjacency[v2] << v1
        end

        visited_edges = Set.new
        rings = []

        adjacency.each_key do |start_vertex|
          next if adjacency[start_vertex].all? { |neighbor| visited_edges.include?([start_vertex, neighbor].sort) }

          ring = trace_ring(start_vertex, adjacency, visited_edges)
          rings << ring if ring && ring.size >= 3
        end

        rings
      end

      def trace_ring(start, adjacency, visited_edges)
        ring = [start]
        current = start

        loop do
          # Find unvisited neighbor
          next_vertex = adjacency[current].find do |neighbor|
            !visited_edges.include?([current, neighbor].sort)
          end

          break unless next_vertex

          visited_edges.add([current, next_vertex].sort)
          break if next_vertex == start # Ring closed

          ring << next_vertex
          current = next_vertex

          # Safety: prevent infinite loops
          break if ring.size > 10_000
        end

        # Close the ring (GeoJSON requires first == last)
        ring << ring.first if ring.size >= 3 && ring.first != ring.last
        ring.size >= 4 ? ring : nil # At least 3 unique + closing point
      end

      def compute_centroid_from_h3(h3_indexes)
        total_lat = 0.0
        total_lng = 0.0

        h3_indexes.each do |h3_hex|
          h3_int = h3_hex.to_i(16)
          lat, lng = H3.to_geo_coordinates(h3_int)
          total_lat += lat
          total_lng += lng
        end

        count = h3_indexes.size.to_f
        { lat: (total_lat / count).round(PRECISION), lng: (total_lng / count).round(PRECISION) }
      end

      def compute_from_bbox
        lat_min = @zone.lat_min.to_f
        lat_max = @zone.lat_max.to_f
        lng_min = @zone.lng_min.to_f
        lng_max = @zone.lng_max.to_f

        {
          type: 'Polygon',
          coordinates: [[
            [lng_min, lat_min],
            [lng_max, lat_min],
            [lng_max, lat_max],
            [lng_min, lat_max],
            [lng_min, lat_min] # Close the ring
          ]]
        }
      end

      def bbox_centroid
        {
          lat: ((@zone.lat_min.to_f + @zone.lat_max.to_f) / 2).round(PRECISION),
          lng: ((@zone.lng_min.to_f + @zone.lng_max.to_f) / 2).round(PRECISION)
        }
      end
    end
  end
end
