# frozen_string_literal: true

module RoutePricing
  module Admin
    class QuoteFailuresController < ApplicationController
      # GET /route_pricing/admin/quote_failures?city_code=hyd&hours=24&limit=100
      def index
        city_code = (params[:city_code] || 'hyd').to_s.downcase
        hours = (params[:hours] || 24).to_i
        limit = [(params[:limit] || 100).to_i, 500].min
        code_filter = params[:failure_code]

        scope = PricingQuoteFailure.for_city(city_code).recent(hours)
        scope = scope.by_code(code_filter) if code_filter.present?

        failures = scope.order(created_at: :desc).limit(limit).map do |f|
          {
            id: f.id,
            city_code: f.city_code,
            vehicle_type: f.vehicle_type,
            failure_code: f.failure_code,
            error_message: f.error_message,
            http_status: f.http_status,
            pickup_lat: f.pickup_lat&.to_f,
            pickup_lng: f.pickup_lng&.to_f,
            drop_lat: f.drop_lat&.to_f,
            drop_lng: f.drop_lng&.to_f,
            pickup_h3_r7: f.pickup_h3_r7,
            drop_h3_r7: f.drop_h3_r7,
            request_id: f.request_id,
            created_at: f.created_at.iso8601
          }
        end

        # Aggregate stats by failure code
        code_counts = PricingQuoteFailure.for_city(city_code).recent(hours)
                                         .group(:failure_code).count
        vehicle_counts = PricingQuoteFailure.for_city(city_code).recent(hours)
                                            .where.not(vehicle_type: nil)
                                            .group(:vehicle_type).count

        render json: {
          city_code: city_code,
          hours: hours,
          total: failures.size,
          code_counts: code_counts,
          vehicle_counts: vehicle_counts,
          failures: failures
        }
      rescue StandardError => e
        Rails.logger.error("QuoteFailures index failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
