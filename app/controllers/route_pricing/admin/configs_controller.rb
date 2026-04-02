# frozen_string_literal: true

module RoutePricing
  module Admin
    class ConfigsController < ApplicationController
      # PATCH /route_pricing/admin/update_config
      def update
        config = PricingConfig.find_by(id: params[:config_id])
        
        unless config
          return render json: { error: "Config not found" }, status: :not_found
        end

        # Create new version
        new_config = config.create_new_version(
          params.require(:updates).permit(
            :base_fare_paise, :per_km_rate_paise, :min_fare_paise,
            :per_min_rate_paise, :dead_km_enabled, :free_pickup_radius_m,
            :dead_km_per_km_rate_paise, :base_distance_m, :timezone,
            :quote_validity_minutes
          ).to_h,
          current_user # TODO: Implement authentication
        )

        render json: {
          success: true,
          config_id: new_config.id,
          version: new_config.version
        }, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /route_pricing/admin/submit_for_approval
      def submit_for_approval
        config = PricingConfig.find_by(id: params[:config_id])
        unless config
          return render json: { error: 'Config not found' }, status: :not_found
        end

        config.submit_for_approval!(params[:submitted_by] || 'admin')

        PricingChangeLog.log!(config, 'submit_for_approval', params[:submitted_by] || 'admin',
                              before: { approval_status: 'draft' },
                              after: { approval_status: 'pending' })

        render json: { success: true, config_id: config.id, approval_status: config.approval_status }, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /route_pricing/admin/approve_config
      def approve_config
        config = PricingConfig.find_by(id: params[:config_id])
        unless config
          return render json: { error: 'Config not found' }, status: :not_found
        end

        # Check for emergency freeze
        if PricingEmergencyFreeze.city_frozen?(config.city_code)
          return render json: { error: 'Cannot approve: pricing is frozen for this city' }, status: :forbidden
        end

        config.approve!(params[:reviewed_by] || 'admin')

        PricingChangeLog.log!(config, 'approve', params[:reviewed_by] || 'admin',
                              before: { approval_status: 'pending' },
                              after: { approval_status: 'approved', active: true })

        render json: { success: true, config_id: config.id, approval_status: config.approval_status }, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /route_pricing/admin/reject_config
      def reject_config
        config = PricingConfig.find_by(id: params[:config_id])
        unless config
          return render json: { error: 'Config not found' }, status: :not_found
        end

        unless params[:reason].present?
          return render json: { error: 'Rejection reason is required' }, status: :bad_request
        end

        config.reject!(params[:reviewed_by] || 'admin', params[:reason])

        PricingChangeLog.log!(config, 'reject', params[:reviewed_by] || 'admin',
                              before: { approval_status: 'pending' },
                              after: { approval_status: 'rejected', rejection_reason: params[:reason] })

        render json: { success: true, config_id: config.id, approval_status: config.approval_status }, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /route_pricing/admin/list_configs
      def index
        configs = PricingConfig.all
        configs = configs.where(city_code: params[:city_code]) if params[:city_code]
        configs = configs.where(vehicle_type: params[:vehicle_type]) if params[:vehicle_type]
        configs = configs.active if params[:active_only] == 'true'

        render json: {
          configs: configs.map do |config|
            {
              id: config.id,
              city_code: config.city_code,
              vehicle_type: config.vehicle_type,
              version: config.version,
              active: config.active,
              effective_from: config.effective_from,
              effective_until: config.effective_until,
              surge_rules: config.pricing_surge_rules.active.map do |rule|
                {
                  id: rule.id,
                  rule_type: rule.rule_type,
                  multiplier: rule.multiplier,
                  priority: rule.priority
                }
              end
            }
          end
        }, status: :ok
      end

      private

      def current_user
        # TODO: Implement JWT authentication
        nil
      end
    end
  end
end
