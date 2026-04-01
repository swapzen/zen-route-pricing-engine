# frozen_string_literal: true

module RoutePricing
  module Admin
    class AutoZonesController < ApplicationController
      # POST /route_pricing/admin/auto_zones/preview
      def preview
        city_code = params[:city_code] || 'hyd'

        result = RoutePricing::AutoZones::Orchestrator.new(city_code, dry_run: true).run!

        render json: result, status: :ok
      rescue StandardError => e
        Rails.logger.error("AutoZones preview failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # POST /route_pricing/admin/auto_zones/generate
      def generate
        city_code = params[:city_code] || 'hyd'

        result = RoutePricing::AutoZones::Orchestrator.new(city_code).run!

        if result[:success]
          render json: result, status: :ok
        else
          render json: result, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("AutoZones generate failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/auto_zones/stats
      def stats
        city_code = params[:city_code] || 'hyd'

        auto_zones = Zone.for_city(city_code).where(auto_generated: true)
        manual_zones = Zone.for_city(city_code).where(auto_generated: false).active

        by_type = auto_zones.group(:zone_type).count
        versions = auto_zones.distinct.pluck(:generation_version).compact.sort

        render json: {
          city_code: city_code,
          manual_zones: manual_zones.count,
          auto_zones: auto_zones.count,
          auto_zones_active: auto_zones.active.count,
          total_cells: auto_zones.sum(:cell_count),
          generation_versions: versions,
          by_type: by_type
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("AutoZones stats failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/auto_zones/cells
      # Returns H3 cells for map rendering. Default: R7 (smooth boundaries via majority-zone dedup).
      # Pass resolution=8 for precise R8 cells. Pricing always uses R8 internally.
      def cells
        city_code = params[:city_code] || 'hyd'
        include_manual = ActiveModel::Type::Boolean.new.cast(params.fetch(:include_manual, true))
        resolution = params[:resolution].to_i
        resolution = 7 unless [7, 8].include?(resolution)

        zones_scope = Zone.for_city(city_code)
        zones_scope = zones_scope.where(auto_generated: true) unless include_manual
        zones = zones_scope.to_a
        zone_ids = zones.map(&:id)
        zone_lookup = zones.index_by(&:id)

        mappings = ZoneH3Mapping.where(zone_id: zone_ids)

        auto_count = 0
        manual_count = 0

        if resolution == 8
          # R8 mode: one cell per R8 mapping
          cells_data = mappings.where.not(h3_index_r8: nil).select(:h3_index_r8, :zone_id, :serviceable).map do |m|
            zone = zone_lookup[m.zone_id]
            next unless zone

            h3_int = m.h3_index_r8.to_i(16)
            lat, lng = H3.to_geo_coordinates(h3_int)
            boundary = H3.to_boundary(h3_int).map { |c| [c[0].round(6), c[1].round(6)] }

            zone.auto_generated? ? (auto_count += 1) : (manual_count += 1)

            {
              h3_index: m.h3_index_r8, resolution: 8,
              lat: lat.round(6), lng: lng.round(6),
              zone_id: m.zone_id, zone_code: zone.zone_code, zone_type: zone.zone_type,
              auto_generated: zone.auto_generated?, active: zone.status?,
              serviceable: m.serviceable != false, boundary: boundary
            }
          end.compact
        else
          # R7 mode: deduplicate R7 hexes — majority zone wins
          r7_groups = Hash.new { |h, k| h[k] = Hash.new(0) }
          r7_serviceable = Hash.new(true)

          mappings.select(:h3_index_r7, :zone_id, :serviceable).each do |m|
            r7_groups[m.h3_index_r7][m.zone_id] += 1
            r7_serviceable[m.h3_index_r7] = false if m.serviceable == false
          end

          cells_data = r7_groups.map do |r7_hex, zone_counts|
            winner_zone_id = zone_counts.max_by(&:last).first
            zone = zone_lookup[winner_zone_id]
            next unless zone

            h3_int = r7_hex.to_i(16)
            lat, lng = H3.to_geo_coordinates(h3_int)
            boundary = H3.to_boundary(h3_int).map { |c| [c[0].round(6), c[1].round(6)] }

            zone.auto_generated? ? (auto_count += 1) : (manual_count += 1)

            {
              h3_index: r7_hex, resolution: 7,
              lat: lat.round(6), lng: lng.round(6),
              zone_id: winner_zone_id, zone_code: zone.zone_code, zone_type: zone.zone_type,
              auto_generated: zone.auto_generated?, active: zone.status?,
              serviceable: r7_serviceable[r7_hex], boundary: boundary
            }
          end.compact
        end

        render json: {
          city_code: city_code,
          resolution: resolution,
          total_cells: cells_data.size,
          auto_cells: auto_count,
          manual_cells: manual_count,
          cells: cells_data
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("AutoZones cells failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # PATCH /route_pricing/admin/auto_zones/toggle_cell
      # Enables or disables a specific H3 cell for pricing.
      # When toggling an R7 cell, updates all R8 children in that R7 hex.
      def toggle_cell
        h3_index = params[:h3_index]
        city_code = params[:city_code] || 'hyd'
        serviceable = ActiveModel::Type::Boolean.new.cast(params[:serviceable])

        if h3_index.blank?
          render json: { error: 'h3_index is required' }, status: :unprocessable_entity
          return
        end

        if serviceable.nil?
          render json: { error: 'serviceable is required' }, status: :unprocessable_entity
          return
        end

        # Try R8 first, then R7 (toggling R7 updates all R8 children in that hex)
        mappings = ZoneH3Mapping.for_city(city_code).for_r8(h3_index)
        mappings = ZoneH3Mapping.for_city(city_code).for_r7(h3_index) if mappings.empty?

        if mappings.empty?
          render json: { error: "No mapping found for h3_index #{h3_index} in #{city_code}" }, status: :not_found
          return
        end

        mappings.update_all(serviceable: serviceable)
        mapping = mappings.first

        zone = mapping.zone
        display_hex = mapping.h3_index_r8 || mapping.h3_index_r7
        h3_int = display_hex.to_i(16)
        lat, lng = H3.to_geo_coordinates(h3_int)
        boundary = H3.to_boundary(h3_int).map { |c| [c[0].round(6), c[1].round(6)] }

        render json: {
          success: true,
          updated_count: mappings.size,
          cell: {
            h3_index: display_hex,
            lat: lat.round(6), lng: lng.round(6),
            zone_id: mapping.zone_id, zone_code: zone&.zone_code,
            zone_type: zone&.zone_type, auto_generated: zone&.auto_generated?,
            active: zone&.status?, serviceable: serviceable,
            boundary: boundary
          }
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("AutoZones toggle_cell failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # DELETE /route_pricing/admin/auto_zones/remove
      def remove
        city_code = params[:city_code] || 'hyd'

        auto_zones = Zone.for_city(city_code).where(auto_generated: true)
        count = auto_zones.count

        if count.zero?
          render json: { success: true, message: 'No auto-generated zones to remove' }, status: :ok
          return
        end

        auto_zones.destroy_all

        render json: { success: true, removed: count }, status: :ok
      rescue StandardError => e
        Rails.logger.error("AutoZones remove failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end
    end
  end
end
