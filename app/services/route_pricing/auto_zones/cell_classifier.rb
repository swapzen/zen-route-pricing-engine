# frozen_string_literal: true

module RoutePricing
  module AutoZones
    class CellClassifier
      # Classifies unassigned H3 cells by zone_type using:
      # Pass 1: Direct inheritance from manual zone bbox containment
      # Pass 2: KNN from nearest manual zone centers

      def initialize(cells:, city_code:, classifier_config:)
        @cells = cells
        @city_code = city_code
        @k = classifier_config['k'] || 3
        @max_distance_km = classifier_config['max_distance_km'] || 5.0
        @default_type = classifier_config['default_type'] || 'outer_ring'
      end

      # Returns Array of { h3_index_r7:, lat:, lng:, zone_type:, confidence:, parent_zone_code: }
      def classify
        manual_zones = load_manual_zones
        return @cells.map { |c| c.merge(zone_type: @default_type, confidence: :low, parent_zone_code: nil) } if manual_zones.empty?

        classified = []
        remaining = []

        # Pass 1: Direct bbox inheritance
        @cells.each do |cell|
          zone = find_containing_zone(cell[:lat], cell[:lng], manual_zones)
          if zone
            classified << cell.merge(
              zone_type: zone.zone_type,
              confidence: :high,
              parent_zone_code: zone.zone_code
            )
          else
            remaining << cell
          end
        end

        # Pass 2: KNN classification for remaining cells
        zone_centers = manual_zones.map { |z| { zone: z, lat: zone_center_lat(z), lng: zone_center_lng(z) } }

        remaining.each do |cell|
          result = knn_classify(cell, zone_centers)
          classified << cell.merge(result)
        end

        Rails.logger.info "[CellClassifier] #{classified.count { |c| c[:confidence] == :high }} high, " \
                          "#{classified.count { |c| c[:confidence] == :medium }} medium, " \
                          "#{classified.count { |c| c[:confidence] == :low }} low confidence"
        classified
      end

      private

      def load_manual_zones
        Zone.for_city(@city_code).active.where(auto_generated: false).to_a
      end

      def find_containing_zone(lat, lng, zones)
        zones.find { |z| z.contains_point_bbox?(lat, lng) }
      end

      def zone_center_lat(zone)
        return nil unless zone.lat_min && zone.lat_max
        (zone.lat_min.to_f + zone.lat_max.to_f) / 2.0
      end

      def zone_center_lng(zone)
        return nil unless zone.lng_min && zone.lng_max
        (zone.lng_min.to_f + zone.lng_max.to_f) / 2.0
      end

      def knn_classify(cell, zone_centers)
        distances = zone_centers.filter_map do |zc|
          next unless zc[:lat] && zc[:lng]
          dist = haversine_km(cell[:lat], cell[:lng], zc[:lat], zc[:lng])
          { zone: zc[:zone], distance: dist }
        end

        distances.sort_by! { |d| d[:distance] }
        nearest = distances.first(@k)

        # All neighbors too far away
        if nearest.empty? || nearest.first[:distance] > @max_distance_km
          return { zone_type: @default_type, confidence: :low, parent_zone_code: nil }
        end

        # Weighted vote by inverse distance
        votes = Hash.new(0.0)
        parent_votes = Hash.new(0.0)

        nearest.each do |n|
          next if n[:distance] > @max_distance_km
          weight = 1.0 / [n[:distance], 0.1].max
          zone_type = n[:zone].zone_type
          votes[zone_type] += weight
          parent_votes["#{zone_type}:#{n[:zone].zone_code}"] += weight
        end

        if votes.empty?
          return { zone_type: @default_type, confidence: :low, parent_zone_code: nil }
        end

        winner_type = votes.max_by { |_, w| w }.first
        total_weight = votes.values.sum
        winner_weight = votes[winner_type]

        # Determine confidence
        confidence = if nearest.all? { |n| n[:zone].zone_type == winner_type }
                       :high
                     elsif winner_weight > total_weight * 0.5
                       :medium
                     else
                       :low
                     end

        # Find parent zone (most weighted contributor of the winner type)
        parent_code = parent_votes
          .select { |k, _| k.start_with?("#{winner_type}:") }
          .max_by { |_, w| w }
          &.first
          &.split(':')
          &.last

        { zone_type: winner_type, confidence: confidence, parent_zone_code: parent_code }
      end

      # Haversine distance in kilometers
      def haversine_km(lat1, lng1, lat2, lng2)
        r = 6371.0
        dlat = to_rad(lat2 - lat1)
        dlng = to_rad(lng2 - lng1)
        a = Math.sin(dlat / 2)**2 +
            Math.cos(to_rad(lat1)) * Math.cos(to_rad(lat2)) * Math.sin(dlng / 2)**2
        2 * r * Math.asin(Math.sqrt(a))
      end

      def to_rad(deg)
        deg * Math::PI / 180.0
      end
    end
  end
end
