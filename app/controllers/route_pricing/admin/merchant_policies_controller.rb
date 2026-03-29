# frozen_string_literal: true

module RoutePricing
  module Admin
    class MerchantPoliciesController < ApplicationController
      # GET /route_pricing/admin/merchant_policies
      def index
        policies = MerchantPricingPolicy.all
        policies = policies.where(merchant_id: params[:merchant_id]) if params[:merchant_id].present?
        policies = policies.where(city_code: params[:city_code]) if params[:city_code].present?
        policies = policies.where(active: true) if params[:active_only] == 'true'
        policies = policies.order(priority: :desc, created_at: :desc)

        render json: {
          policies: policies.map { |p| format_policy(p) }
        }, status: :ok
      end

      # POST /route_pricing/admin/merchant_policies
      def create
        policy = MerchantPricingPolicy.create!(policy_params)

        PricingChangeLog.log!(policy, 'create', params[:actor] || 'admin',
                              after: policy.attributes)

        render json: { success: true, policy: format_policy(policy) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # PATCH /route_pricing/admin/merchant_policies/:id
      def update
        policy = MerchantPricingPolicy.find(params[:id])
        before = policy.attributes.dup

        policy.update!(policy_params)

        PricingChangeLog.log!(policy, 'update', params[:actor] || 'admin',
                              before: before, after: policy.attributes)

        render json: { success: true, policy: format_policy(policy) }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Policy not found' }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # DELETE /route_pricing/admin/merchant_policies/:id
      def destroy
        policy = MerchantPricingPolicy.find(params[:id])
        policy.update!(active: false)

        PricingChangeLog.log!(policy, 'deactivate', params[:actor] || 'admin',
                              before: { active: true }, after: { active: false })

        render json: { success: true }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Policy not found' }, status: :not_found
      end

      # POST /route_pricing/admin/merchant_policies/simulate
      def simulate
        unless params[:merchant_id].present? && params[:base_price_paise].present?
          return render json: { error: 'merchant_id and base_price_paise required' }, status: :bad_request
        end

        result = MerchantPricingPolicy.apply_policies(
          params[:merchant_id],
          params[:base_price_paise].to_i,
          city: params[:city_code],
          vehicle: params[:vehicle_type]
        )

        render json: {
          merchant_id: params[:merchant_id],
          base_price_paise: params[:base_price_paise].to_i,
          final_price_paise: result[:final_price_paise],
          adjustments: result[:adjustments]
        }, status: :ok
      end

      private

      def policy_params
        params.permit(:merchant_id, :merchant_name, :city_code, :vehicle_type,
                      :policy_type, :value_paise, :value_pct, :priority,
                      :active, :effective_from, :effective_until, metadata: {})
      end

      def format_policy(policy)
        {
          id: policy.id,
          merchant_id: policy.merchant_id,
          merchant_name: policy.merchant_name,
          city_code: policy.city_code,
          vehicle_type: policy.vehicle_type,
          policy_type: policy.policy_type,
          value_paise: policy.value_paise,
          value_pct: policy.value_pct,
          priority: policy.priority,
          active: policy.active,
          effective_from: policy.effective_from,
          effective_until: policy.effective_until,
          created_at: policy.created_at.iso8601
        }
      end
    end
  end
end
