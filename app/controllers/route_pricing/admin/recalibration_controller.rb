# frozen_string_literal: true

module RoutePricing
  module Admin
    class RecalibrationController < ApplicationController
      # POST /route_pricing/admin/recalibration/optimize
      # Run optimizer on benchmark data, return recommendations
      def optimize
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        benchmarks = params[:benchmarks]
        unless benchmarks.is_a?(Array) && benchmarks.any?
          return render json: { error: 'benchmarks array is required' }, status: :bad_request
        end

        optimizer = RoutePricing::Services::RecalibrationOptimizer.new(
          city_code: params[:city_code],
          time_bands: params[:time_bands],
          vehicle_types: params[:vehicle_types]
        )

        result = optimizer.optimize(
          benchmarks.map { |b| benchmark_params(b) },
          dry_run: params[:dry_run] != false
        )

        render json: result, status: :ok
      rescue StandardError => e
        Rails.logger.error("RecalibrationOptimizer failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # POST /route_pricing/admin/recalibration/simulate
      # Dry-run: given proposed changes, return projected pass rate + per-route impact
      def simulate
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        benchmarks = params[:benchmarks]
        changes = params[:changes]

        unless benchmarks.is_a?(Array) && benchmarks.any?
          return render json: { error: 'benchmarks array is required' }, status: :bad_request
        end

        unless changes.is_a?(Array) && changes.any?
          return render json: { error: 'changes array is required' }, status: :bad_request
        end

        optimizer = RoutePricing::Services::RecalibrationOptimizer.new(
          city_code: params[:city_code]
        )

        result = optimizer.simulate(
          benchmarks.map { |b| benchmark_params(b) },
          changes.map { |c| change_params(c) }
        )

        render json: result, status: :ok
      rescue StandardError => e
        Rails.logger.error("RecalibrationSimulate failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # POST /route_pricing/admin/recalibration/snapshots
      def create_snapshot
        unless params[:city_code].present?
          return render json: { error: 'city_code is required' }, status: :bad_request
        end

        manager = RoutePricing::Services::PricingSnapshotManager.new
        snapshot = manager.capture(
          params[:city_code],
          params[:name] || "Snapshot #{Time.current.strftime('%Y-%m-%d %H:%M')}",
          params[:description] || '',
          created_by: params[:created_by]
        )

        render json: {
          id: snapshot.id,
          name: snapshot.name,
          city_code: snapshot.city_code,
          created_at: snapshot.created_at
        }, status: :created
      rescue StandardError => e
        Rails.logger.error("CreateSnapshot failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/recalibration/snapshots
      def list_snapshots
        city_code = params[:city_code] || 'hyd'
        manager = RoutePricing::Services::PricingSnapshotManager.new
        snapshots = manager.list(city_code)

        render json: snapshots.map { |s|
          {
            id: s.id,
            name: s.name,
            city_code: s.city_code,
            description: s.description,
            created_by: s.created_by,
            created_at: s.created_at
          }
        }, status: :ok
      end

      # POST /route_pricing/admin/recalibration/snapshots/:id/restore
      def restore_snapshot
        manager = RoutePricing::Services::PricingSnapshotManager.new
        result = manager.restore(params[:id])

        if result[:success]
          render json: result, status: :ok
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Snapshot not found' }, status: :not_found
      rescue StandardError => e
        Rails.logger.error("RestoreSnapshot failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/recalibration/snapshots/:id/compare
      def compare_snapshot
        manager = RoutePricing::Services::PricingSnapshotManager.new
        diff = manager.compare(params[:id])

        render json: diff, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Snapshot not found' }, status: :not_found
      rescue StandardError => e
        Rails.logger.error("CompareSnapshot failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      private

      def benchmark_params(b)
        b.permit(
          :origin_zone_id, :dest_zone_id, :vehicle_type, :time_band,
          :benchmark_price_paise, :distance_m, :duration_min
        ).to_h.symbolize_keys
      end

      def change_params(c)
        c.permit(
          :pricing_type, :zone_id, :from_zone_id, :to_zone_id,
          :vehicle_type, :time_band, :field, :new_value
        ).to_h.symbolize_keys
      end
    end
  end
end
