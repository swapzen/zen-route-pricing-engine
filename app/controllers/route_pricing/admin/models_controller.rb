# frozen_string_literal: true

module RoutePricing
  module Admin
    class ModelsController < ApplicationController
      # GET /route_pricing/admin/models/scores
      def scores
        scores = PricingModelScore.all
        scores = scores.for_city(params[:city_code]) if params[:city_code].present?
        scores = scores.for_model(params[:model_version]) if params[:model_version].present?
        scores = scores.order(created_at: :desc).limit((params[:limit] || 50).to_i)

        render json: {
          scores: scores.map do |s|
            {
              id: s.id,
              quote_id: s.pricing_quote_id,
              model_version: s.model_version,
              city_code: s.city_code,
              vehicle_type: s.vehicle_type,
              deterministic_price: s.deterministic_price_paise,
              model_suggested: s.model_suggested_paise,
              delta_paise: s.model_suggested_paise && s.deterministic_price_paise ?
                             s.model_suggested_paise - s.deterministic_price_paise : nil,
              expected_acceptance_pct: s.expected_acceptance_pct,
              expected_margin_pct: s.expected_margin_pct,
              outcome: s.outcome,
              created_at: s.created_at.iso8601
            }
          end
        }, status: :ok
      end

      # GET /route_pricing/admin/models/accuracy
      def accuracy
        scores = PricingModelScore.with_outcomes
        scores = scores.for_city(params[:city_code]) if params[:city_code].present?
        scores = scores.for_model(params[:model_version]) if params[:model_version].present?

        if scores.empty?
          return render json: { message: 'No scored outcomes available' }, status: :ok
        end

        total = scores.count
        accepted = scores.where(outcome: 'accepted').count
        predicted_acceptances = scores.where('expected_acceptance_pct > 50')
        correctly_predicted = predicted_acceptances.where(outcome: 'accepted').count

        avg_delta = scores.average(
          Arel.sql('ABS(model_suggested_paise - deterministic_price_paise)')
        )&.round || 0

        render json: {
          total_scored: total,
          outcomes_breakdown: scores.group(:outcome).count,
          acceptance_prediction_accuracy: predicted_acceptances.count > 0 ?
            (correctly_predicted.to_f / predicted_acceptances.count * 100).round(2) : nil,
          avg_price_delta_paise: avg_delta,
          model_versions: scores.distinct.pluck(:model_version)
        }, status: :ok
      end

      # POST /route_pricing/admin/models/configure
      def configure
        config = PricingModelConfig.find_or_initialize_by(
          algorithm_name: params[:algorithm_name],
          city_code: params[:city_code]
        )

        before = config.persisted? ? config.attributes.dup : {}

        config.assign_attributes(
          model_version: params[:model_version] || config.model_version || 'v1',
          mode: params[:mode] || config.mode,
          canary_pct: (params[:canary_pct] || config.canary_pct || 0).to_i,
          active: params[:active] != false && params[:active] != 'false',
          parameters: params[:parameters] || config.parameters || {}
        )
        config.save!

        PricingChangeLog.log!(config, config.previously_new_record? ? 'create' : 'update',
                              params[:actor] || 'admin',
                              before: before, after: config.attributes)

        render json: {
          success: true,
          config: {
            id: config.id,
            algorithm_name: config.algorithm_name,
            model_version: config.model_version,
            mode: config.mode,
            canary_pct: config.canary_pct,
            city_code: config.city_code,
            active: config.active,
            parameters: config.parameters
          }
        }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /route_pricing/admin/models/comparison
      def comparison
        scores = PricingModelScore.all
        scores = scores.for_city(params[:city_code]) if params[:city_code].present?
        scores = scores.order(created_at: :desc).limit((params[:limit] || 50).to_i)

        render json: {
          comparisons: scores.map do |s|
            delta = s.model_suggested_paise && s.deterministic_price_paise ?
                      s.model_suggested_paise - s.deterministic_price_paise : nil
            delta_pct = delta && s.deterministic_price_paise&.positive? ?
                          (delta.to_f / s.deterministic_price_paise * 100).round(2) : nil
            {
              quote_id: s.pricing_quote_id,
              model_version: s.model_version,
              deterministic: s.deterministic_price_paise,
              model_suggested: s.model_suggested_paise,
              delta_paise: delta,
              delta_pct: delta_pct,
              outcome: s.outcome,
              created_at: s.created_at.iso8601
            }
          end
        }, status: :ok
      end
    end
  end
end
