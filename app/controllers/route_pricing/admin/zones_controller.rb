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

      # PATCH /route_pricing/admin/zones/:id/multiplier
      # Body: { zone_multiplier: 0.85 }  — range 0.5 to 2.0
      def update_multiplier
        zone = Zone.find(params[:id])
        raw = params[:zone_multiplier].to_s.strip
        multiplier = raw.blank? ? nil : raw.to_f

        if multiplier && (multiplier < 0.5 || multiplier > 2.0)
          return render json: { error: 'zone_multiplier must be between 0.5 and 2.0' }, status: :unprocessable_entity
        end

        zone.update!(zone_multiplier: multiplier)

        # Invalidate caches so the new multiplier takes effect immediately.
        Rails.cache.delete_matched("pricing:*") rescue nil

        render json: {
          id: zone.id,
          zone_code: zone.zone_code,
          zone_multiplier: zone.zone_multiplier,
          effective_zone_multiplier: zone.effective_zone_multiplier,
          message: "Multiplier for #{zone.zone_code} set to #{zone.effective_zone_multiplier}"
        }
      end
    end
  end
end
