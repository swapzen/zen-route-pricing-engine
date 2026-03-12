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
      # Returns H3 cells with coordinates and boundaries for map rendering.
      # By default includes both manual and auto-generated zone cells.
      # Pass include_manual=false to show only auto-generated zone cells.
      def cells
        city_code = params[:city_code] || 'hyd'
        include_manual = ActiveModel::Type::Boolean.new.cast(params.fetch(:include_manual, true))

        zones_scope = Zone.for_city(city_code)
        zones_scope = zones_scope.where(auto_generated: true) unless include_manual
        zones = zones_scope.to_a
        zone_ids = zones.map(&:id)
        zone_lookup = zones.index_by(&:id)

        mappings = ZoneH3Mapping.where(zone_id: zone_ids).select(:h3_index_r7, :zone_id, :serviceable)

        auto_count = 0
        manual_count = 0

        cells_data = mappings.map do |m|
          zone = zone_lookup[m.zone_id]
          next unless zone

          h3_int = m.h3_index_r7.to_i(16)
          lat, lng = H3.to_geo_coordinates(h3_int)
          boundary = H3.to_boundary(h3_int).map { |coords| [coords[0].round(6), coords[1].round(6)] }

          is_auto = zone.auto_generated?
          if is_auto
            auto_count += 1
          else
            manual_count += 1
          end

          {
            h3_index: m.h3_index_r7,
            lat: lat.round(6),
            lng: lng.round(6),
            zone_id: m.zone_id,
            zone_code: zone.zone_code,
            zone_type: zone.zone_type,
            auto_generated: is_auto,
            active: zone.status?,
            serviceable: m.serviceable != false,
            boundary: boundary
          }
        end.compact

        render json: {
          city_code: city_code,
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

        mapping = ZoneH3Mapping.for_city(city_code).for_r7(h3_index).first

        unless mapping
          render json: { error: "No mapping found for h3_index #{h3_index} in #{city_code}" }, status: :not_found
          return
        end

        mapping.update!(serviceable: serviceable)

        zone = mapping.zone
        h3_int = mapping.h3_index_r7.to_i(16)
        lat, lng = H3.to_geo_coordinates(h3_int)
        boundary = H3.to_boundary(h3_int).map { |coords| [coords[0].round(6), coords[1].round(6)] }

        render json: {
          success: true,
          cell: {
            h3_index: mapping.h3_index_r7,
            lat: lat.round(6),
            lng: lng.round(6),
            zone_id: mapping.zone_id,
            zone_code: zone&.zone_code,
            zone_type: zone&.zone_type,
            auto_generated: zone&.auto_generated?,
            active: zone&.status?,
            serviceable: mapping.serviceable,
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
