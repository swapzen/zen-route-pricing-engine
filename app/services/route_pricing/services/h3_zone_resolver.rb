# frozen_string_literal: true

module RoutePricing
  module Services
    class H3ZoneResolver
      CACHE_TTL = 24.hours

      def initialize(city_code)
        @city_code = city_code
      end

      # Resolve a lat/lng point to a Zone using H3 hexagonal grid.
      # Algorithm:
      # 1. Point → R7 hex
      # 2. Redis cache lookup: h3_r7:{city}:{hex} → zone_id
      # 3. If boundary cell → R9 hex → h3_r9:{city}:{hex} → zone_id
      # 4. If R9 miss → highest-priority zone from R7 mappings
      # 5. Returns Zone or nil (caller falls back to bounding box)
      def resolve(lat, lng)
        return nil unless h3_available?

        h3_r7 = H3.from_geo_coordinates([lat.to_f, lng.to_f], 7).to_s(16)

        # Try R7 cache first
        cached_zone_id = read_cache("h3_r7:#{@city_code}:#{h3_r7}")
        if cached_zone_id
          return cached_zone_id == 'nil' ? nil : Zone.find_by(id: cached_zone_id)
        end

        # DB lookup for R7 (only serviceable cells)
        mappings = ZoneH3Mapping.find_zones_for_r7(h3_r7, @city_code)
        mappings = mappings.where(serviceable: true) if ZoneH3Mapping.column_names.include?('serviceable')
        mappings = mappings.to_a

        if mappings.empty?
          write_cache("h3_r7:#{@city_code}:#{h3_r7}", 'nil')
          return nil
        end

        # Single zone match — done
        if mappings.size == 1
          zone = mappings.first.zone
          write_cache("h3_r7:#{@city_code}:#{h3_r7}", zone.id.to_s)
          return zone
        end

        # Boundary cell: try R9 disambiguation
        zone = resolve_boundary(lat, lng, mappings)
        zone
      rescue StandardError => e
        Rails.logger.debug("H3ZoneResolver error: #{e.message}")
        nil
      end

      private

      def resolve_boundary(lat, lng, r7_mappings)
        h3_r9 = H3.from_geo_coordinates([lat.to_f, lng.to_f], 9).to_s(16)

        # Try R9 cache
        cached_zone_id = read_cache("h3_r9:#{@city_code}:#{h3_r9}")
        if cached_zone_id
          return cached_zone_id == 'nil' ? nil : Zone.find_by(id: cached_zone_id)
        end

        # R9 DB lookup (only serviceable cells)
        r9_scope = ZoneH3Mapping.for_city(@city_code).for_r9(h3_r9).includes(:zone)
        r9_scope = r9_scope.where(serviceable: true) if ZoneH3Mapping.column_names.include?('serviceable')
        r9_mapping = r9_scope.first
        if r9_mapping
          zone = r9_mapping.zone
          write_cache("h3_r9:#{@city_code}:#{h3_r9}", zone.id.to_s)
          return zone
        end

        # Fallback: highest-priority zone from R7 mappings
        zone = r7_mappings.map(&:zone).max_by { |z| [z.priority || 0, -(z.zone_code || '').ord] }
        write_cache("h3_r9:#{@city_code}:#{h3_r9}", zone&.id.to_s || 'nil')
        zone
      end

      def h3_available?
        defined?(H3) && defined?(ZoneH3Mapping) && ZoneH3Mapping.table_exists?
      rescue StandardError
        false
      end

      def read_cache(key)
        Rails.cache.read(key)
      rescue StandardError
        nil
      end

      def write_cache(key, value)
        Rails.cache.write(key, value, expires_in: CACHE_TTL)
      rescue StandardError
        # Cache write failure is non-fatal
      end
    end
  end
end
