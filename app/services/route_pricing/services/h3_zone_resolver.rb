# frozen_string_literal: true

module RoutePricing
  module Services
    class H3ZoneResolver
      CACHE_TTL = 2.hours
      PRIMARY_RESOLUTION = 8
      FALLBACK_RESOLUTION = 7

      @@city_maps = {}
      @@map_loaded_at = {}
      @@mutex = Mutex.new

      def initialize(city_code)
        @city_code = city_code.to_s.downcase
      end

      # Resolve a lat/lng point to a Zone using H3 hexagonal grid.
      # Algorithm:
      # 1. Point -> R8 hex -> in-memory hash map -> zone_id (O(1) lookup)
      # 2. If R8 miss: Point -> R7 hex (parent) -> in-memory hash map -> zone_id
      # 3. Returns Zone or nil (caller falls back to bounding box)
      def resolve(lat, lng)
        return nil unless h3_available?

        # Primary: Res 8 lookup (in-memory, O(1))
        h3_r8 = H3.from_geo_coordinates([lat.to_f, lng.to_f], PRIMARY_RESOLUTION).to_s(16)
        zone_id = city_map_r8[h3_r8]
        return Zone.find_by(id: zone_id) if zone_id

        # Fallback: Res 7 (parent hex)
        h3_r7 = H3.from_geo_coordinates([lat.to_f, lng.to_f], FALLBACK_RESOLUTION).to_s(16)
        zone_id = city_map_r7[h3_r7]
        return Zone.find_by(id: zone_id) if zone_id

        nil
      rescue StandardError => e
        Rails.logger.debug("H3ZoneResolver error: #{e.message}")
        nil
      end

      # Build in-memory hash maps for a city from the database.
      # R8 map: loaded directly from DB zone_h3_mappings (h3_index_r8 column).
      #   Each R8 cell maps to exactly one zone — no overlaps by construction.
      # R7 map: derived from R8 — for each R7 parent, pick the zone with most R8 children.
      #   Used as fallback when R8 lookup misses (point near cell boundary).
      # Returns { r8: count, r7: count } of loaded entries.
      def self.build_city_map(city_code)
        city_code = city_code.to_s.downcase

        r8_map = {}
        r7_zone_counts = Hash.new { |h, k| h[k] = Hash.new(0) } # r7_hex → { zone_id → count }

        scope = ZoneH3Mapping.for_city(city_code).includes(:zone)
        scope = scope.where(serviceable: true) if ZoneH3Mapping.column_names.include?('serviceable')

        scope.find_each do |mapping|
          zone = mapping.zone
          next unless zone&.active?

          # Primary: R8 direct lookup (no overlap possible)
          if mapping.h3_index_r8.present?
            r8_map[mapping.h3_index_r8] = zone.id
            # Track R7 parent for fallback map
            r7_parent = H3.parent(mapping.h3_index_r8.to_i(16), FALLBACK_RESOLUTION).to_s(16)
            r7_zone_counts[r7_parent][zone.id] += 1
          elsif mapping.h3_index_r7.present?
            # Legacy R7-only mappings: expand to R8 children
            r7_hex = mapping.h3_index_r7
            begin
              H3.children(r7_hex.to_i(16), PRIMARY_RESOLUTION).each do |r8_int|
                r8_key = r8_int.to_s(16)
                r8_map[r8_key] ||= zone.id  # first-write wins (no overwrite)
              end
            rescue StandardError => e
              Rails.logger.debug("H3ZoneResolver: R8 expansion failed for #{r7_hex}: #{e.message}")
            end
            r7_zone_counts[r7_hex][zone.id] += 7  # approximate
          end
        end

        # R7 fallback: for each R7 parent, pick the zone with most R8 children
        r7_map = {}
        r7_zone_counts.each do |r7_hex, counts|
          r7_map[r7_hex] = counts.max_by(&:last).first
        end

        @@mutex.synchronize do
          @@city_maps["#{city_code}_r8"] = r8_map
          @@city_maps["#{city_code}_r7"] = r7_map
          @@map_loaded_at[city_code] = Time.current
        end

        { r8: r8_map.size, r7: r7_map.size }
      end

      # Clear in-memory cache for a city (or all cities if nil).
      def self.invalidate!(city_code = nil)
        @@mutex.synchronize do
          if city_code
            cc = city_code.to_s.downcase
            @@city_maps.delete("#{cc}_r8")
            @@city_maps.delete("#{cc}_r7")
            @@map_loaded_at.delete(cc)
          else
            @@city_maps = {}
            @@map_loaded_at = {}
          end
        end
      end

      private

      def city_map_r8
        ensure_loaded!
        @@city_maps["#{@city_code}_r8"] || {}
      end

      def city_map_r7
        ensure_loaded!
        @@city_maps["#{@city_code}_r7"] || {}
      end

      def ensure_loaded!
        if stale?
          self.class.build_city_map(@city_code)
        end
      end

      def stale?
        loaded_at = @@map_loaded_at[@city_code]
        loaded_at.nil? || (Time.current - loaded_at) > CACHE_TTL
      end

      def h3_available?
        defined?(H3) && defined?(ZoneH3Mapping) && ZoneH3Mapping.table_exists?
      rescue StandardError
        false
      end
    end
  end
end
