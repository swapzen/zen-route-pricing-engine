# frozen_string_literal: true

module RoutePricing
  module Admin
    class SurgeBucketsController < ApplicationController
      # GET /route_pricing/admin/surge_buckets
      # Params: city_code (required), time_band (optional)
      def index
        unless params[:city_code].present?
          return render json: { error: "city_code is required" }, status: :bad_request
        end

        scope = H3SurgeBucket.for_city(params[:city_code]).active
        scope = scope.for_time_band(params[:time_band]) if params[:time_band].present?
        scope = scope.surging if params[:surging_only] == 'true'
        scope = scope.order(surge_multiplier: :desc)

        buckets = scope.limit(params[:limit] || 500)

        render json: {
          city_code: params[:city_code],
          time_band: params[:time_band],
          count: buckets.size,
          buckets: buckets.map { |b| serialize_bucket(b) }
        }, status: :ok
      end

      # POST /route_pricing/admin/surge_buckets
      # Upsert a single surge bucket by h3_index + city_code + time_band
      def create
        unless params[:h3_index].present? && params[:city_code].present?
          return render json: { error: "h3_index and city_code are required" }, status: :bad_request
        end

        bucket = H3SurgeBucket.find_or_initialize_by(
          h3_index: params[:h3_index],
          city_code: params[:city_code].to_s.downcase,
          time_band: params[:time_band]
        )

        bucket.assign_attributes(
          surge_multiplier: params[:surge_multiplier] || bucket.surge_multiplier || 1.0,
          demand_score: params[:demand_score] || bucket.demand_score || 0.0,
          supply_score: params[:supply_score] || bucket.supply_score || 0.0,
          h3_resolution: params[:h3_resolution] || 9,
          expires_at: params[:expires_at],
          source: params[:source] || 'manual',
          metadata: params[:metadata] || bucket.metadata || {}
        )

        if bucket.save
          render json: {
            success: true,
            bucket: serialize_bucket(bucket),
            action: bucket.previously_new_record? ? 'created' : 'updated'
          }, status: bucket.previously_new_record? ? :created : :ok
        else
          render json: { error: bucket.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end
      end

      # POST /route_pricing/admin/surge_buckets/bulk_update
      # Update multiple hex surge values at once (for heatmap painting)
      # Params: city_code, buckets: [{ h3_index:, surge_multiplier:, ... }]
      def bulk_update
        unless params[:city_code].present? && params[:buckets].is_a?(Array)
          return render json: { error: "city_code and buckets array are required" }, status: :bad_request
        end

        city_code = params[:city_code].to_s.downcase
        results = { created: 0, updated: 0, errors: [] }

        ActiveRecord::Base.transaction do
          params[:buckets].each_with_index do |bucket_params, idx|
            unless bucket_params[:h3_index].present?
              results[:errors] << { index: idx, error: "h3_index is required" }
              next
            end

            bucket = H3SurgeBucket.find_or_initialize_by(
              h3_index: bucket_params[:h3_index],
              city_code: city_code,
              time_band: bucket_params[:time_band]
            )

            bucket.assign_attributes(
              surge_multiplier: bucket_params[:surge_multiplier] || 1.0,
              demand_score: bucket_params[:demand_score] || 0.0,
              supply_score: bucket_params[:supply_score] || 0.0,
              h3_resolution: bucket_params[:h3_resolution] || 9,
              expires_at: bucket_params[:expires_at],
              source: bucket_params[:source] || 'manual',
              metadata: bucket_params[:metadata] || {}
            )

            if bucket.save
              bucket.previously_new_record? ? results[:created] += 1 : results[:updated] += 1
            else
              results[:errors] << { index: idx, h3_index: bucket_params[:h3_index], error: bucket.errors.full_messages.join(', ') }
            end
          end
        end

        render json: {
          success: results[:errors].empty?,
          created: results[:created],
          updated: results[:updated],
          errors: results[:errors]
        }, status: results[:errors].empty? ? :ok : :multi_status
      end

      # GET /route_pricing/admin/surge_buckets/heatmap
      # Returns surge data for an area around a center point
      # Params: city_code, lat, lng, k_ring_size (default 2), time_band (optional)
      def heatmap
        unless params[:city_code].present? && params[:lat].present? && params[:lng].present?
          return render json: { error: "city_code, lat, and lng are required" }, status: :bad_request
        end

        resolver = RoutePricing::Services::H3SurgeResolver.new(params[:city_code])
        hexes = resolver.resolve_area(
          params[:lat].to_f,
          params[:lng].to_f,
          k_ring_size: (params[:k_ring_size] || 2).to_i,
          time_band: params[:time_band]
        )

        summary = resolver.city_surge_summary(time_band: params[:time_band])

        render json: {
          city_code: params[:city_code],
          center: { lat: params[:lat].to_f, lng: params[:lng].to_f },
          k_ring_size: (params[:k_ring_size] || 2).to_i,
          time_band: params[:time_band],
          hexes: hexes,
          summary: summary
        }, status: :ok
      end

      # DELETE /route_pricing/admin/surge_buckets/clear
      # Clear all surge for a city or specific time_band
      # Params: city_code (required), time_band (optional)
      def clear
        unless params[:city_code].present?
          return render json: { error: "city_code is required" }, status: :bad_request
        end

        scope = H3SurgeBucket.for_city(params[:city_code])
        scope = scope.where(time_band: params[:time_band]) if params[:time_band].present?

        deleted_count = scope.delete_all

        # Invalidate surge caches for this city
        Rails.cache.delete_matched("surge:#{params[:city_code].to_s.downcase}:*") rescue nil

        render json: {
          success: true,
          deleted: deleted_count,
          city_code: params[:city_code],
          time_band: params[:time_band]
        }, status: :ok
      end

      private

      def serialize_bucket(bucket)
        {
          id: bucket.id,
          h3_index: bucket.h3_index,
          city_code: bucket.city_code,
          h3_resolution: bucket.h3_resolution,
          surge_multiplier: bucket.surge_multiplier,
          demand_score: bucket.demand_score,
          supply_score: bucket.supply_score,
          time_band: bucket.time_band,
          expires_at: bucket.expires_at,
          source: bucket.source,
          metadata: bucket.metadata,
          created_at: bucket.created_at,
          updated_at: bucket.updated_at
        }
      end
    end
  end
end
