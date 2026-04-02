# frozen_string_literal: true

module RoutePricing
  module Admin
    class CompetitorBenchmarksController < ApplicationController
      # GET /route_pricing/admin/competitor_benchmarks
      def index
        city_code = params[:city_code] || 'hyd'
        time_band = params[:time_band]

        benchmarks = CompetitorBenchmark.for_city(city_code)
        benchmarks = benchmarks.for_band(time_band) if time_band.present?

        render json: {
          success: true,
          benchmarks: benchmarks.map { |b|
            {
              id: b.id,
              route_key: b.route_key,
              pickup_address: b.pickup_address,
              drop_address: b.drop_address,
              vehicle_type: b.vehicle_type,
              time_band: b.time_band,
              porter_price_inr: b.porter_price_inr,
              our_price_inr: b.our_price_inr,
              delta_pct: b.delta_pct,
              distance_m: b.distance_m,
              status: b.status
            }
          }
        }
      end

      # POST /route_pricing/admin/competitor_benchmarks/bulk_save
      def bulk_save
        entries = params[:benchmarks] || []
        saved = 0
        errors = []

        entries.each do |entry|
          benchmark = CompetitorBenchmark.find_or_initialize_by(
            route_key: entry[:route_key],
            vehicle_type: entry[:vehicle_type],
            time_band: entry[:time_band]
          )

          benchmark.assign_attributes(
            city_code: entry[:city_code] || 'hyd',
            pickup_address: entry[:pickup_address],
            drop_address: entry[:drop_address],
            pickup_lat: entry[:pickup_lat],
            pickup_lng: entry[:pickup_lng],
            drop_lat: entry[:drop_lat],
            drop_lng: entry[:drop_lng],
            porter_price_inr: entry[:porter_price_inr],
            our_price_inr: entry[:our_price_inr],
            distance_m: entry[:distance_m],
            entered_by: entry[:entered_by] || 'admin',
            status: 'entered'
          )

          if benchmark.save
            saved += 1
          else
            errors << { route_key: entry[:route_key], vehicle_type: entry[:vehicle_type], errors: benchmark.errors.full_messages }
          end
        end

        render json: { success: true, saved: saved, errors: errors }
      end

      # POST /route_pricing/admin/competitor_benchmarks/recalibrate
      def recalibrate
        city_code = params[:city_code] || 'hyd'
        time_band = params[:time_band]

        report = RoutePricing::Services::CompetitorRecalibrator.new(
          city_code: city_code,
          time_band: time_band
        ).run

        render json: { success: true, report: report }
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
