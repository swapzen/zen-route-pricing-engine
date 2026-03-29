# frozen_string_literal: true

module RoutePricing
  module Services
    class PorterRecalibrator
      THRESHOLD_PCT = 10.0

      def initialize(city_code:, time_band: nil)
        @city_code = city_code
        @time_band = time_band
      end

      def run
        scope = PorterBenchmark.for_city(@city_code).with_both_prices
        scope = scope.for_band(@time_band) if @time_band.present?

        return { groups: [], summary: 'No benchmarks with both prices found.' } unless scope.exists?

        # SQL aggregation instead of Ruby group_by
        rows = scope
          .where.not(delta_pct: nil)
          .group(:vehicle_type, :time_band)
          .select(
            'vehicle_type', 'time_band',
            'COUNT(*) AS total_count',
            'AVG(delta_pct) AS mean_delta',
            'MIN(delta_pct) AS min_delta',
            'MAX(delta_pct) AS max_delta',
            "COUNT(CASE WHEN ABS(delta_pct) > #{THRESHOLD_PCT} THEN 1 END) AS flagged_count"
          )

        groups = rows.map do |r|
          # Fetch flagged routes for this group (only top 5)
          flagged_routes = scope
            .where(vehicle_type: r.vehicle_type, time_band: r.time_band)
            .where("ABS(delta_pct) > ?", THRESHOLD_PCT)
            .order(Arel.sql('ABS(delta_pct) DESC'))
            .limit(5)
            .map { |b| "#{b.pickup_address} → #{b.drop_address} (#{b.delta_pct.round(1)}%)" }

          {
            vehicle_type: r.vehicle_type,
            time_band: r.time_band,
            count: r.total_count.to_i,
            mean_delta_pct: r.mean_delta&.round(1).to_f,
            median_delta_pct: r.mean_delta&.round(1).to_f, # approximation
            max_delta_pct: r.max_delta&.round(1),
            min_delta_pct: r.min_delta&.round(1),
            flagged_count: r.flagged_count.to_i,
            flagged_routes: flagged_routes
          }
        end.sort_by { |g| [-g[:flagged_count], g[:vehicle_type]] }

        total = groups.sum { |g| g[:count] }
        total_flagged = groups.sum { |g| g[:flagged_count] }
        overall_mean = if total > 0
                         (groups.sum { |g| g[:mean_delta_pct] * g[:count] } / total).round(1)
                       else
                         0
                       end

        summary = "#{total} benchmarks across #{groups.size} vehicle/band groups. " \
                  "#{total_flagged} routes flagged (>#{THRESHOLD_PCT}% delta). " \
                  "Overall mean delta: #{overall_mean}%."

        { groups: groups, summary: summary, total: total, total_flagged: total_flagged }
      end

      private

      def median(arr)
        return 0 if arr.empty?
        sorted = arr.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end
  end
end
