# frozen_string_literal: true

module RoutePricing
  module AutoZones
    class ZoneClusterer
      # Groups adjacent classified cells of the same zone_type into zones
      # using flood-fill on H3 neighbors, then post-processes:
      # - Merges clusters below min_cells into nearest neighbor
      # - Splits clusters above max_cells via k-means on cell centers

      def initialize(classified_cells:, clustering_config:, naming_config:)
        @cells = classified_cells
        @min_cells = clustering_config['min_cells'] || 3
        @max_cells = clustering_config['max_cells'] || 50
        @merge_orphans = clustering_config['merge_orphans'] != false
        @prefix = naming_config['prefix'] || 'auto'
      end

      # Returns Array of cluster hashes:
      # { zone_code:, zone_type:, cells: [...], bounds: {}, parent_zone_code: }
      def cluster
        # Build lookup: h3_index -> cell
        cell_map = @cells.each_with_object({}) { |c, h| h[c[:h3_index_r7]] = c }

        # Group by zone_type, then flood-fill connected components
        by_type = @cells.group_by { |c| c[:zone_type] }
        raw_clusters = []

        by_type.each do |zone_type, type_cells|
          components = flood_fill(type_cells, cell_map)
          components.each do |component|
            raw_clusters << {
              zone_type: zone_type,
              cells: component,
              parent_zone_code: most_common_parent(component)
            }
          end
        end

        # Post-process: merge small, split large
        clusters = post_process(raw_clusters)

        # Assign zone codes
        assign_zone_codes(clusters)

        Rails.logger.info "[ZoneClusterer] #{clusters.size} clusters from #{@cells.size} cells"
        clusters
      end

      private

      def flood_fill(type_cells, cell_map)
        hex_set = type_cells.map { |c| c[:h3_index_r7] }.to_set
        visited = Set.new
        components = []

        type_cells.each do |cell|
          hex = cell[:h3_index_r7]
          next if visited.include?(hex)

          # BFS from this cell
          component = []
          queue = [hex]

          while queue.any?
            current = queue.shift
            next if visited.include?(current)
            next unless hex_set.include?(current)

            visited.add(current)
            component << cell_map[current]

            # H3 neighbors (k_ring=1 gives the cell + 6 neighbors)
            neighbors = H3.k_ring(current.to_i(16), 1)
            neighbors.each do |neighbor_int|
              neighbor_hex = neighbor_int.to_s(16)
              queue << neighbor_hex if hex_set.include?(neighbor_hex) && !visited.include?(neighbor_hex)
            end
          end

          components << component if component.any?
        end

        components
      end

      def post_process(clusters)
        result = []
        orphans = []

        clusters.each do |cluster|
          if cluster[:cells].size < @min_cells
            orphans << cluster
          elsif cluster[:cells].size > @max_cells
            result.concat(split_cluster(cluster))
          else
            result << cluster
          end
        end

        # Merge orphans
        if @merge_orphans && orphans.any?
          orphans.each do |orphan|
            merged = merge_orphan(orphan, result)
            result << orphan unless merged
          end
        else
          # Keep orphans as-is if merge disabled
          result.concat(orphans)
        end

        result
      end

      def split_cluster(cluster)
        cells = cluster[:cells]
        k = (cells.size.to_f / @max_cells).ceil
        k = [k, 2].max

        # Simple k-means on lat/lng
        centroids = cells.sample(k).map { |c| [c[:lat], c[:lng]] }
        assignments = nil

        10.times do # max iterations
          assignments = cells.map do |cell|
            centroids.each_with_index.min_by { |centroid, _| euclidean_sq(cell[:lat], cell[:lng], centroid[0], centroid[1]) }.last
          end

          new_centroids = Array.new(k) { |i|
            assigned = cells.each_with_index.select { |_, j| assignments[j] == i }.map(&:first)
            if assigned.any?
              [assigned.sum { |c| c[:lat] } / assigned.size, assigned.sum { |c| c[:lng] } / assigned.size]
            else
              centroids[i]
            end
          }

          break if new_centroids == centroids
          centroids = new_centroids
        end

        # Group by assignment
        groups = cells.each_with_index.group_by { |_, j| assignments[j] }
        groups.map do |_, group_cells|
          gc = group_cells.map(&:first)
          {
            zone_type: cluster[:zone_type],
            cells: gc,
            parent_zone_code: most_common_parent(gc)
          }
        end
      end

      def merge_orphan(orphan, clusters)
        return false if clusters.empty?

        orphan_center = cluster_center(orphan[:cells])

        # Prefer same-type clusters, then any
        same_type = clusters.select { |c| c[:zone_type] == orphan[:zone_type] }
        candidates = same_type.any? ? same_type : clusters

        nearest = candidates.min_by do |c|
          center = cluster_center(c[:cells])
          euclidean_sq(orphan_center[0], orphan_center[1], center[0], center[1])
        end

        nearest[:cells].concat(orphan[:cells])
        true
      end

      def assign_zone_codes(clusters)
        counters = Hash.new(0)

        clusters.each do |cluster|
          counters[cluster[:zone_type]] += 1
          seq = counters[cluster[:zone_type]].to_s.rjust(3, '0')
          cluster[:zone_code] = "#{@prefix}_#{cluster[:zone_type]}_#{seq}"
          cluster[:bounds] = compute_bounds(cluster[:cells])
        end
      end

      def compute_bounds(cells)
        lats = cells.map { |c| c[:lat] }
        lngs = cells.map { |c| c[:lng] }
        {
          lat_min: lats.min,
          lat_max: lats.max,
          lng_min: lngs.min,
          lng_max: lngs.max
        }
      end

      def cluster_center(cells)
        [
          cells.sum { |c| c[:lat] } / cells.size.to_f,
          cells.sum { |c| c[:lng] } / cells.size.to_f
        ]
      end

      def most_common_parent(cells)
        parents = cells.map { |c| c[:parent_zone_code] }.compact
        return nil if parents.empty?
        parents.tally.max_by { |_, count| count }.first
      end

      def euclidean_sq(lat1, lng1, lat2, lng2)
        (lat1 - lat2)**2 + (lng1 - lng2)**2
      end
    end
  end
end
