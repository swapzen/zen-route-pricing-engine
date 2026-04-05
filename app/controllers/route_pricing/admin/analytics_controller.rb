# frozen_string_literal: true

module RoutePricing
  module Admin
    class AnalyticsController < ApplicationController
      # GET /route_pricing/admin/analytics/distance_distribution?city_code=hyd&days=30
      # Buckets PricingQuote.distance_m into 2km bins per vehicle_type.
      def distance_distribution
        city_code = (params[:city_code] || 'hyd').to_s.downcase
        days = [(params[:days] || 30).to_i, 365].min
        bucket_km = (params[:bucket_km] || 2).to_i

        scope = PricingQuote
                  .where(city_code: city_code)
                  .where('created_at >= ?', days.days.ago)
                  .where.not(distance_m: nil)

        total = scope.count
        if total.zero?
          return render json: {
            city_code: city_code, days: days, total: 0,
            buckets: [], by_vehicle: {}
          }
        end

        # Overall bucket distribution
        bucket_m = bucket_km * 1000
        raw = scope.pluck(:distance_m, :vehicle_type)
        by_bucket = Hash.new(0)
        by_vehicle_bucket = Hash.new { |h, k| h[k] = Hash.new(0) }

        raw.each do |dist, vt|
          bucket = (dist.to_i / bucket_m) * bucket_km
          by_bucket[bucket] += 1
          by_vehicle_bucket[vt][bucket] += 1
        end

        max_bucket = by_bucket.keys.max || 0
        buckets = (0..max_bucket).step(bucket_km).map do |b|
          count = by_bucket[b] || 0
          { range: "#{b}-#{b + bucket_km}km", min_km: b, count: count, pct: (count.to_f / total * 100).round(1) }
        end

        by_vehicle = by_vehicle_bucket.transform_values do |h|
          h.map { |b, c| { min_km: b, count: c } }.sort_by { |x| x[:min_km] }
        end

        # Summary stats
        distances_km = raw.map { |d, _| d.to_f / 1000 }
        median = distances_km.sort[distances_km.size / 2]
        mean = distances_km.sum / distances_km.size
        p90 = distances_km.sort[(distances_km.size * 0.9).to_i]

        render json: {
          city_code: city_code,
          days: days,
          total: total,
          bucket_km: bucket_km,
          buckets: buckets,
          by_vehicle: by_vehicle,
          stats: {
            mean_km: mean.round(2),
            median_km: median.round(2),
            p90_km: p90.round(2),
            min_km: distances_km.min.round(2),
            max_km: distances_km.max.round(2)
          }
        }
      rescue StandardError => e
        Rails.logger.error("distance_distribution failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/analytics/rejection_reasons?city_code=hyd&days=30
      def rejection_reasons
        city_code = (params[:city_code] || 'hyd').to_s.downcase
        days = [(params[:days] || 30).to_i, 365].min

        scope = PricingOutcome.for_city(city_code).where('created_at >= ?', days.days.ago)

        by_outcome = scope.group(:outcome).count
        by_reason = scope.where.not(rejection_reason: nil).group(:rejection_reason).count
        by_vehicle = scope.where(outcome: 'rejected').group(:vehicle_type).count
        by_time_band = scope.where(outcome: 'rejected').group(:time_band).count
        by_zone = scope.where(outcome: 'rejected')
                       .group(:pickup_zone_code).count
                       .sort_by { |_, c| -c }
                       .first(10)
                       .to_h

        total = by_outcome.values.sum
        acceptance_rate = total.zero? ? 0 : ((by_outcome['accepted'] || 0).to_f / total * 100).round(1)
        rejection_rate = total.zero? ? 0 : ((by_outcome['rejected'] || 0).to_f / total * 100).round(1)

        render json: {
          city_code: city_code,
          days: days,
          total: total,
          acceptance_rate: acceptance_rate,
          rejection_rate: rejection_rate,
          by_outcome: by_outcome,
          by_reason: by_reason,
          by_vehicle: by_vehicle,
          by_time_band: by_time_band,
          top_rejecting_zones: by_zone
        }
      rescue StandardError => e
        Rails.logger.error("rejection_reasons failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
