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
        benchmarks = PorterBenchmark.for_city(@city_code).with_both_prices
        benchmarks = benchmarks.for_band(@time_band) if @time_band.present?

        return { groups: [], summary: 'No benchmarks with both prices found.' } if benchmarks.empty?

        grouped = benchmarks.group_by { |b| [b.vehicle_type, b.time_band] }

        groups = grouped.map do |(vehicle_type, time_band), items|
          deltas = items.map(&:delta_pct).compact.sort
          next nil if deltas.empty?

          flagged = items.select { |b| b.delta_pct.to_f.abs > THRESHOLD_PCT }
                        .map { |b| "#{b.pickup_address} → #{b.drop_address} (#{b.delta_pct.round(1)}%)" }

          {
            vehicle_type: vehicle_type,
            time_band: time_band,
            count: items.size,
            mean_delta_pct: (deltas.sum / deltas.size).round(1),
            median_delta_pct: median(deltas).round(1),
            max_delta_pct: deltas.max_by(&:abs)&.round(1),
            min_delta_pct: deltas.min_by(&:abs)&.round(1),
            flagged_count: flagged.size,
            flagged_routes: flagged.first(5)
          }
        end.compact.sort_by { |g| [-g[:flagged_count], g[:vehicle_type]] }

        total = groups.sum { |g| g[:count] }
        total_flagged = groups.sum { |g| g[:flagged_count] }
        overall_mean = if groups.any?
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
