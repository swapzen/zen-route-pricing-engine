# frozen_string_literal: true

module RoutePricing
  module Admin
    class MarketStateController < ApplicationController
      # GET /route_pricing/admin/market/dashboard
      def dashboard
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        aggregator = RoutePricing::Services::MarketStateAggregator.new(
          city_code: params[:city_code],
          lookback_hours: (params[:lookback_hours] || 24).to_i
        )

        render json: aggregator.dashboard, status: :ok
      rescue StandardError => e
        Rails.logger.error("MarketState dashboard failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/market/zone_health
      def zone_health
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        aggregator = RoutePricing::Services::MarketStateAggregator.new(
          city_code: params[:city_code],
          lookback_hours: (params[:lookback_hours] || 24).to_i
        )

        render json: { zones: aggregator.zone_health }, status: :ok
      rescue StandardError => e
        Rails.logger.error("MarketState zone_health failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/market/pressure_map
      def pressure_map
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        aggregator = RoutePricing::Services::MarketStateAggregator.new(
          city_code: params[:city_code],
          lookback_hours: (params[:lookback_hours] || 24).to_i
        )

        render json: { hexes: aggregator.pressure_map }, status: :ok
      rescue StandardError => e
        Rails.logger.error("MarketState pressure_map failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
