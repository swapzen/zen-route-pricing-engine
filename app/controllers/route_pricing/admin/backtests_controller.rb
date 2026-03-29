# frozen_string_literal: true

module RoutePricing
  module Admin
    class BacktestsController < ApplicationController
      # POST /route_pricing/admin/backtests
      def create
        backtest = PricingBacktest.create!(
          city_code: params[:city_code],
          candidate_config_id: params[:candidate_config_id],
          baseline_config_id: params[:baseline_config_id],
          sample_size: (params[:sample_size] || 100).to_i,
          triggered_by: params[:triggered_by] || 'admin'
        )

        # Run inline for small samples, could be async for large
        runner = RoutePricing::Services::BacktestRunner.new(backtest)
        runner.run!

        render json: {
          backtest_id: backtest.id,
          status: backtest.status,
          results: backtest.results,
          completed_replays: backtest.completed_replays
        }, status: :created
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
      rescue StandardError => e
        Rails.logger.error("Backtest create failed: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /route_pricing/admin/backtests/:id
      def show
        backtest = PricingBacktest.find(params[:id])

        render json: {
          backtest_id: backtest.id,
          city_code: backtest.city_code,
          status: backtest.status,
          sample_size: backtest.sample_size,
          completed_replays: backtest.completed_replays,
          results: backtest.results,
          replay_details: backtest.replay_details,
          started_at: backtest.started_at&.iso8601,
          completed_at: backtest.completed_at&.iso8601,
          triggered_by: backtest.triggered_by
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Backtest not found' }, status: :not_found
      end

      # GET /route_pricing/admin/backtests
      def index
        backtests = PricingBacktest.all
        backtests = backtests.for_city(params[:city_code]) if params[:city_code].present?
        backtests = backtests.where(status: params[:status]) if params[:status].present?
        backtests = backtests.order(created_at: :desc).limit((params[:limit] || 20).to_i)

        render json: {
          backtests: backtests.map do |bt|
            {
              id: bt.id,
              city_code: bt.city_code,
              status: bt.status,
              sample_size: bt.sample_size,
              completed_replays: bt.completed_replays,
              pass: bt.results&.dig('pass'),
              triggered_by: bt.triggered_by,
              created_at: bt.created_at.iso8601
            }
          end
        }, status: :ok
      end
    end
  end
end
