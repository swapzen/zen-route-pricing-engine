# frozen_string_literal: true

module RoutePricing
  module Admin
    class SurgeRulesController < ApplicationController
      # POST /route_pricing/admin/create_surge_rule
      def create
        config = PricingConfig.find_by(id: params[:config_id])
        
        unless config
          return render json: { error: "Config not found" }, status: :not_found
        end

        rule = PricingSurgeRule.create!(
          pricing_config: config,
          rule_type: params[:rule_type],
          condition_json: params[:condition_json],
          multiplier: BigDecimal(params[:multiplier].to_s),
          priority: params[:priority] || 100,
          notes: params[:notes],
          created_by: current_user, # TODO: Implement authentication
          active: true
        )

        render json: {
          success: true,
          rule_id: rule.id,
          rule_type: rule.rule_type,
          multiplier: rule.multiplier
        }, status: :created
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # PATCH /route_pricing/admin/deactivate_surge_rule
      def deactivate
        rule = PricingSurgeRule.find_by(id: params[:rule_id])
        
        unless rule
          return render json: { error: "Rule not found" }, status: :not_found
        end

        rule.update!(active: false)

        render json: {
          success: true,
          rule_id: rule.id,
          active: rule.active
        }, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def current_user
        # TODO: Implement JWT authentication
        nil
      end
    end
  end
end
