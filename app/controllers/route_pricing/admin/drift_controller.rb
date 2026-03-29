# frozen_string_literal: true

module RoutePricing
  module Admin
    class DriftController < ApplicationController
      # GET /route_pricing/admin/drift_report
      def drift_report
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        analyzer = RoutePricing::Services::DriftAnalyzer.new(
          city_code: params[:city_code],
          lookback_days: (params[:lookback_days] || 7).to_i,
          threshold_pct: (params[:threshold_pct] || 15).to_f
        )

        render json: analyzer.analyze, status: :ok
      rescue StandardError => e
        Rails.logger.error("DriftReport failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/drift_summary
      def drift_summary
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        analyzer = RoutePricing::Services::DriftAnalyzer.new(
          city_code: params[:city_code],
          lookback_days: (params[:lookback_days] || 7).to_i
        )

        render json: analyzer.summary, status: :ok
      rescue StandardError => e
        Rails.logger.error("DriftSummary failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
