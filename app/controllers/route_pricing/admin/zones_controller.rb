# frozen_string_literal: true

module RoutePricing
  module Admin
    class ZonesController < ApplicationController
      before_action :authenticate_api_key!

      # PATCH /route_pricing/admin/zones/:id/toggle
      def toggle
        zone = Zone.find(params[:id])

        new_status = !zone.status
        zone.update!(status: new_status)

        # Cascade to H3 mappings
        ZoneH3Mapping.where(zone_id: zone.id).update_all(serviceable: new_status)

        # Invalidate H3 resolver cache
        RoutePricing::Services::H3ZoneResolver.invalidate!(zone.city)

        render json: {
          id: zone.id,
          zone_code: zone.zone_code,
          status: zone.status,
          message: "Zone #{zone.zone_code} #{new_status ? 'activated' : 'deactivated'}"
        }
      end
    end
  end
end
