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
          params[:updates].permit!.to_h,
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
