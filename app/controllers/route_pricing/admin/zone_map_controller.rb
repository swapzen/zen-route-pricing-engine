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
            id: z.id.to_s,
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

      # POST /route_pricing/admin/zone_map/compute_boundaries
      def compute_boundaries
        city_code = params[:city_code] || 'hyd'
        result = RoutePricing::Services::ZoneBoundaryComputer.compute_for_city!(city_code)

        render json: { success: true, city_code: city_code, **result }
      rescue StandardError => e
        Rails.logger.error("ZoneMap compute_boundaries failed: #{e.message}")
        render json: { success: false, error: e.message }, status: :internal_server_error
      end

    end
  end
end
