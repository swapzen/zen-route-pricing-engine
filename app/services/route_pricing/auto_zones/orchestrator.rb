# frozen_string_literal: true

module RoutePricing
  module AutoZones
    class Orchestrator
      # Top-level coordinator for H3 auto-zone generation.
      #
      # Pipeline:
      #   1. Load config from YAML
      #   2. Generate city grid → unassigned cells
      #   3. Classify cells → zone_type assignments
      #   4. Cluster cells → zone candidates
      #   5. Persist zones (skip if dry_run)
      #   6. Return stats + preview data

      CITY_FILE_MAPPING = {
        'hyd' => 'hyderabad',
        'blr' => 'bangalore',
        'mum' => 'mumbai',
        'del' => 'delhi',
        'chn' => 'chennai',
        'pun' => 'pune'
      }.freeze

      def initialize(city_code, dry_run: false)
        @city_code = city_code.downcase
        @dry_run = dry_run
        @config = load_config
      end

      def run!
        validate!

        # Step 1: Ensure manual zones have H3 mappings
        ensure_h3_mappings!

        # Step 2: Generate city grid
        cells = generate_grid

        if cells.empty?
          return { success: true, message: 'No unassigned cells — full coverage already', stats: empty_stats }
        end

        # Step 3: Classify cells
        classified = classify_cells(cells)

        # Step 4: Cluster cells
        clusters = cluster_cells(classified)

        # Step 5: Persist (or preview)
        if @dry_run
          build_preview(cells, classified, clusters)
        else
          persist_zones(clusters)
        end
      end

      def preview
        @dry_run = true
        run!
      end

      private

      def validate!
        raise "H3 gem not available" unless defined?(H3)
        raise "No auto-zone config found for #{@city_code}" unless @config
        raise "No boundary defined in config" unless @config['boundary']
      end

      def load_config
        city_folder = CITY_FILE_MAPPING[@city_code] || @city_code
        path = Rails.root.join('config', 'zones', "#{city_folder}_auto_zone.yml")
        return nil unless File.exist?(path)
        YAML.load_file(path)
      end

      def ensure_h3_mappings!
        manual_zones = Zone.for_city(@city_code).active.where(auto_generated: false)
        unmapped = manual_zones.where.not(id: ZoneH3Mapping.select(:zone_id).distinct)

        if unmapped.exists?
          Rails.logger.info "[AutoZones::Orchestrator] #{unmapped.count} manual zones lack H3 mappings — populating..."
          populate_h3_for_zones(unmapped)
        end
      end

      def populate_h3_for_zones(zones)
        zones.find_each do |zone|
          next unless zone.lat_min && zone.lat_max && zone.lng_min && zone.lng_max

          r7_cells = compute_r7_cells_for_bbox(zone)
          r7_cells.each do |r7_hex|
            mapping = ZoneH3Mapping.find_or_initialize_by(
              h3_index_r7: r7_hex,
              zone_id: zone.id
            )
            mapping.assign_attributes(city_code: @city_code, is_boundary: false)
            mapping.save! if mapping.changed? || mapping.new_record?
          end

          zone_r7s = ZoneH3Mapping.where(zone_id: zone.id).pluck(:h3_index_r7).uniq
          zone.update!(h3_indexes_r7: zone_r7s)
        end
      end

      def compute_r7_cells_for_bbox(zone)
        lat_step = 0.003
        lng_step = 0.003
        cells = Set.new

        lat = zone.lat_min.to_f
        while lat <= zone.lat_max.to_f
          lng = zone.lng_min.to_f
          while lng <= zone.lng_max.to_f
            h3_int = H3.from_geo_coordinates([lat, lng], 7)
            cells.add(h3_int.to_s(16))
            lng += lng_step
          end
          lat += lat_step
        end

        cells.to_a
      end

      def generate_grid
        CityGridGenerator.new(
          boundary: @config['boundary'],
          h3_resolution: @config['h3_resolution'] || 7,
          city_code: @city_code
        ).generate
      end

      def classify_cells(cells)
        CellClassifier.new(
          cells: cells,
          city_code: @city_code,
          classifier_config: @config['classifier'] || {}
        ).classify
      end

      def cluster_cells(classified)
        ZoneClusterer.new(
          classified_cells: classified,
          clustering_config: @config['clustering'] || {},
          naming_config: @config['naming'] || {}
        ).cluster
      end

      def persist_zones(clusters)
        version = next_generation_version

        stats = AutoZonePersister.new(
          clusters: clusters,
          city_code: @city_code,
          generation_version: version
        ).persist!

        {
          success: true,
          generation_version: version,
          stats: stats
        }
      end

      def build_preview(cells, classified, clusters)
        type_breakdown = classified.group_by { |c| c[:zone_type] }.transform_values(&:count)
        confidence_breakdown = classified.group_by { |c| c[:confidence] }.transform_values(&:count)

        {
          success: true,
          dry_run: true,
          total_cells: cells.size,
          classified: classified.size,
          type_breakdown: type_breakdown,
          confidence_breakdown: confidence_breakdown,
          clusters: clusters.size,
          cluster_summary: clusters.map { |c|
            { zone_code: c[:zone_code], zone_type: c[:zone_type], cells: c[:cells].size, parent: c[:parent_zone_code] }
          },
          zones_to_create: clusters.size
        }
      end

      def next_generation_version
        current_max = Zone.for_city(@city_code)
                          .where(auto_generated: true)
                          .maximum(:generation_version) || 0
        current_max + 1
      end

      def empty_stats
        { zones_created: 0, cells_mapped: 0, pricing_records: 0 }
      end
    end
  end
end
