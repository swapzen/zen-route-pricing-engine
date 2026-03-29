# frozen_string_literal: true

module RoutePricing
  module Admin
    class ZoneMapController < ApplicationController
      # GET /route_pricing/admin/zone_map/zones?city_code=hyd
      def zones
        city_code = params[:city_code] || 'hyd'

        zones = Zone.for_city(city_code).active
                    .select(:id, :zone_code, :name, :zone_type, :auto_generated, :priority,
                            :cell_count, :parent_zone_code, :boundary_geojson, :center_lat, :center_lng,
                            :lat_min, :lat_max, :lng_min, :lng_max)

        # Check which zones have pricing configured
        zones_with_pricing = ZoneVehiclePricing.where(zone_id: zones.map(&:id), active: true)
                                               .distinct.pluck(:zone_id).to_set

        zones_data = zones.map do |z|
          {
            id: z.id,
            zone_code: z.zone_code,
            name: z.name,
            zone_type: z.zone_type,
            auto_generated: z.auto_generated?,
            priority: z.priority,
            cell_count: z.cell_count,
            parent_zone_code: z.parent_zone_code,
            center_lat: z.center_lat&.to_f,
            center_lng: z.center_lng&.to_f,
            boundary_geojson: z.boundary_geojson,
            has_pricing: zones_with_pricing.include?(z.id)
          }
        end

        render json: {
          city_code: city_code,
          total_zones: zones_data.size,
          manual_zones: zones_data.count { |z| !z[:auto_generated] },
          auto_zones: zones_data.count { |z| z[:auto_generated] },
          zones: zones_data
        }
      rescue StandardError => e
        Rails.logger.error("ZoneMap zones failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/zone_map/corridors?city_code=hyd
      def corridors
        city_code = params[:city_code] || 'hyd'

        # Get unique zone pairs with their metadata
        corridor_records = ZonePairVehiclePricing.where(city_code: city_code, active: true)
                                                 .select(:from_zone_id, :to_zone_id, :auto_generated)
                                                 .distinct

        # Deduplicate pairs
        seen_pairs = Set.new
        pairs = []

        corridor_records.each do |c|
          pair_key = [c.from_zone_id, c.to_zone_id].sort
          next if seen_pairs.include?(pair_key)
          seen_pairs.add(pair_key)

          pairs << {
            from_zone_id: c.from_zone_id,
            to_zone_id: c.to_zone_id,
            auto_generated: c.auto_generated?
          }
        end

        # Fetch zone centers for line rendering
        zone_ids = pairs.flat_map { |p| [p[:from_zone_id], p[:to_zone_id]] }.uniq
        zone_centers = Zone.where(id: zone_ids)
                           .pluck(:id, :zone_code, :center_lat, :center_lng, :zone_type)
                           .each_with_object({}) do |(id, code, lat, lng, type), hash|
          hash[id] = { zone_code: code, center_lat: lat&.to_f, center_lng: lng&.to_f, zone_type: type }
        end

        corridors_data = pairs.map do |pair|
          from_info = zone_centers[pair[:from_zone_id]] || {}
          to_info = zone_centers[pair[:to_zone_id]] || {}

          {
            from_zone_id: pair[:from_zone_id],
            to_zone_id: pair[:to_zone_id],
            from_zone_code: from_info[:zone_code],
            to_zone_code: to_info[:zone_code],
            from_center: { lat: from_info[:center_lat], lng: from_info[:center_lng] },
            to_center: { lat: to_info[:center_lat], lng: to_info[:center_lng] },
            from_zone_type: from_info[:zone_type],
            to_zone_type: to_info[:zone_type],
            auto_generated: pair[:auto_generated]
          }
        end

        render json: {
          city_code: city_code,
          total_corridors: corridors_data.size,
          manual_corridors: corridors_data.count { |c| !c[:auto_generated] },
          auto_corridors: corridors_data.count { |c| c[:auto_generated] },
          corridors: corridors_data
        }
      rescue StandardError => e
        Rails.logger.error("ZoneMap corridors failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/zone_map/zone_pricing_summary?zone_id=X
      def zone_pricing_summary
        zone = Zone.find(params[:zone_id])

        pricings = ZoneVehiclePricing.where(zone_id: zone.id, active: true)
                                     .includes(:zone_vehicle_time_pricings)

        pricing_data = pricings.map do |zvp|
          time_bands = zvp.zone_vehicle_time_pricings.select(&:active?).map do |tp|
            {
              time_band: tp.time_band,
              base_fare_paise: tp.base_fare_paise,
              per_km_rate_paise: tp.per_km_rate_paise,
              per_min_rate_paise: tp.per_min_rate_paise
            }
          end

          {
            vehicle_type: zvp.vehicle_type,
            base_fare_paise: zvp.base_fare_paise,
            per_km_rate_paise: zvp.per_km_rate_paise,
            per_min_rate_paise: zvp.per_min_rate_paise,
            time_bands: time_bands
          }
        end

        render json: {
          zone_id: zone.id,
          zone_code: zone.zone_code,
          zone_type: zone.zone_type,
          pricing: pricing_data
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Zone not found' }, status: :not_found
      rescue StandardError => e
        Rails.logger.error("ZoneMap zone_pricing_summary failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/zone_map/corridor_pricing?from_zone_id=X&to_zone_id=Y
      def corridor_pricing
        from_id = params[:from_zone_id]
        to_id = params[:to_zone_id]

        records = ZonePairVehiclePricing.where(city_code: params[:city_code] || 'hyd', active: true)
                                        .where(
                                          "(from_zone_id = ? AND to_zone_id = ?) OR (from_zone_id = ? AND to_zone_id = ?)",
                                          from_id, to_id, to_id, from_id
                                        )

        from_zone = Zone.find_by(id: from_id)
        to_zone = Zone.find_by(id: to_id)

        pricing_data = records.map do |r|
          {
            vehicle_type: r.vehicle_type,
            time_band: r.time_band,
            base_fare_paise: r.base_fare_paise,
            per_km_rate_paise: r.per_km_rate_paise,
            min_fare_paise: r.min_fare_paise,
            per_min_rate_paise: r.per_min_rate_paise,
            auto_generated: r.auto_generated?,
            directional: r.directional?
          }
        end

        render json: {
          from_zone: { id: from_id, zone_code: from_zone&.zone_code, zone_type: from_zone&.zone_type },
          to_zone: { id: to_id, zone_code: to_zone&.zone_code, zone_type: to_zone&.zone_type },
          pricing: pricing_data
        }
      rescue StandardError => e
        Rails.logger.error("ZoneMap corridor_pricing failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # POST /route_pricing/admin/zone_map/compute_boundaries
      def compute_boundaries
        city_code = params[:city_code] || 'hyd'
        result = RoutePricing::Services::ZoneBoundaryComputer.compute_for_city!(city_code)

        render json: { success: true, city_code: city_code, **result }
      rescue StandardError => e
        Rails.logger.error("ZoneMap compute_boundaries failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

      # POST /route_pricing/admin/zone_map/detect_corridors
      def detect_corridors
        city_code = params[:city_code] || 'hyd'
        detector = RoutePricing::Services::InterZoneDetector.new(city_code)
        stats = detector.detect_and_generate!

        render json: { success: true, city_code: city_code, **stats }
      rescue StandardError => e
        Rails.logger.error("ZoneMap detect_corridors failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end
    end
  end
end
