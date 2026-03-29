# frozen_string_literal: true

module RoutePricing
  module Services
    class MarketStateAggregator
      def initialize(city_code:, lookback_hours: 24)
        @city_code = city_code
        @lookback_hours = lookback_hours
      end

      def dashboard
        return empty_dashboard unless base_scope.exists?

        {
          city_code: @city_code,
          lookback_hours: @lookback_hours,
          overall: overall_metrics,
          by_vehicle: vehicle_breakdown,
          by_time_band: time_band_breakdown,
          hot_zones: hot_zones,
          generated_at: Time.current.iso8601
        }
      end

      def zone_health
        rows = base_scope
          .where.not(pickup_zone_code: [nil, ''])
          .group(:pickup_zone_code)
          .select(
            'pickup_zone_code AS zone_code',
            'COUNT(*) AS total_quotes',
            "COUNT(CASE WHEN outcome = 'accepted' THEN 1 END) AS accepted_count",
            "COUNT(CASE WHEN outcome = 'rejected' THEN 1 END) AS rejected_count",
            'AVG(quoted_price_paise) AS avg_price',
            'AVG(response_time_seconds) AS avg_response_time'
          )

        return [] unless rows.any?

        zone_codes = rows.map(&:zone_code)
        rejection_map = rejection_reasons_by_zone(zone_codes)

        rows.map do |r|
          total = r.total_quotes.to_i
          {
            zone_code: r.zone_code,
            total_quotes: total,
            acceptance_rate: total > 0 ? (r.accepted_count.to_i.to_f / total * 100).round(2) : 0,
            rejection_rate: total > 0 ? (r.rejected_count.to_i.to_f / total * 100).round(2) : 0,
            avg_quoted_price_paise: r.avg_price&.round,
            avg_response_time_s: r.avg_response_time&.round(1),
            top_rejection_reasons: rejection_map[r.zone_code] || {}
          }
        end.sort_by { |z| z[:acceptance_rate] }
      end

      def pressure_map
        rows = base_scope
          .where.not(h3_index_r7: nil)
          .group(:h3_index_r7, :time_band)
          .select(
            'h3_index_r7',
            'time_band',
            'COUNT(*) AS total_quotes',
            "COUNT(CASE WHEN outcome = 'accepted' THEN 1 END) AS accepted_count",
            "COUNT(CASE WHEN outcome = 'rejected' THEN 1 END) AS rejected_count"
          )

        return [] unless rows.any?

        rows.map do |r|
          total = r.total_quotes.to_i
          acceptance_rate = total > 0 ? (r.accepted_count.to_i.to_f / total * 100).round(2) : 0

          supply = H3SupplyDensity.for_cell(
            r.h3_index_r7, @city_code,
            r.time_band || RoutePricing::Services::TimeBandResolver.current_band
          ).first

          {
            h3_index_r7: r.h3_index_r7,
            time_band: r.time_band,
            total_quotes: total,
            acceptance_rate: acceptance_rate,
            rejection_rate: total > 0 ? (r.rejected_count.to_i.to_f / total * 100).round(2) : 0,
            supply_density: supply&.estimated_driver_count,
            pressure_score: compute_pressure(acceptance_rate, supply&.estimated_driver_count, total)
          }
        end.sort_by { |p| -p[:pressure_score] }
      end

      private

      def base_scope
        PricingOutcome.for_city(@city_code).recent(@lookback_hours)
      end

      def overall_metrics
        row = base_scope.select(
          'COUNT(*) AS total_quotes',
          "COUNT(CASE WHEN outcome = 'accepted' THEN 1 END) AS accepted_count",
          "COUNT(CASE WHEN outcome = 'rejected' THEN 1 END) AS rejected_count",
          'AVG(response_time_seconds) AS avg_response_time',
          'AVG(quoted_price_paise) AS avg_price'
        ).take

        total = row.total_quotes.to_i
        {
          total_quotes: total,
          acceptance_rate: total > 0 ? (row.accepted_count.to_i.to_f / total * 100).round(2) : 0,
          rejection_rate: total > 0 ? (row.rejected_count.to_i.to_f / total * 100).round(2) : 0,
          avg_response_time_s: row.avg_response_time&.round(1),
          avg_quoted_price_paise: row.avg_price&.round
        }
      end

      def vehicle_breakdown
        base_scope
          .where.not(vehicle_type: [nil, ''])
          .group(:vehicle_type)
          .select(
            'vehicle_type',
            'COUNT(*) AS total_quotes',
            "COUNT(CASE WHEN outcome = 'accepted' THEN 1 END) AS accepted_count",
            'AVG(quoted_price_paise) AS avg_price'
          )
          .map do |r|
            total = r.total_quotes.to_i
            {
              vehicle_type: r.vehicle_type,
              total_quotes: total,
              acceptance_rate: total > 0 ? (r.accepted_count.to_i.to_f / total * 100).round(2) : 0,
              avg_price_paise: r.avg_price&.round
            }
          end
      end

      def time_band_breakdown
        base_scope
          .where.not(time_band: [nil, ''])
          .group(:time_band)
          .select(
            'time_band',
            'COUNT(*) AS total_quotes',
            "COUNT(CASE WHEN outcome = 'accepted' THEN 1 END) AS accepted_count"
          )
          .map do |r|
            total = r.total_quotes.to_i
            {
              time_band: r.time_band,
              total_quotes: total,
              acceptance_rate: total > 0 ? (r.accepted_count.to_i.to_f / total * 100).round(2) : 0
            }
          end
      end

      def hot_zones
        base_scope
          .where.not(pickup_zone_code: [nil, ''])
          .group(:pickup_zone_code)
          .having('COUNT(*) >= 3')
          .select(
            'pickup_zone_code AS zone_code',
            'COUNT(*) AS total_quotes',
            "COUNT(CASE WHEN outcome = 'rejected' THEN 1 END) AS rejected_count"
          )
          .filter_map do |r|
            total = r.total_quotes.to_i
            rejection_rate = (r.rejected_count.to_i.to_f / total * 100).round(2)
            next nil if rejection_rate < 30

            {
              zone_code: r.zone_code,
              total_quotes: total,
              rejection_rate: rejection_rate,
              top_reasons: rejection_reasons_for(r.zone_code)
            }
          end
          .sort_by { |z| -z[:rejection_rate] }
          .first(10)
      end

      def rejection_reasons_for(zone_code)
        base_scope
          .where(pickup_zone_code: zone_code, outcome: 'rejected')
          .where.not(rejection_reason: [nil, ''])
          .group(:rejection_reason)
          .order(Arel.sql('COUNT(*) DESC'))
          .limit(5)
          .count
      end

      def rejection_reasons_by_zone(zone_codes)
        rows = base_scope
          .where(pickup_zone_code: zone_codes, outcome: 'rejected')
          .where.not(rejection_reason: [nil, ''])
          .group(:pickup_zone_code, :rejection_reason)
          .count

        result = Hash.new { |h, k| h[k] = {} }
        rows.each do |(zone, reason), count|
          result[zone][reason] = count
        end
        # Keep top 5 per zone
        result.transform_values { |reasons| reasons.sort_by { |_, v| -v }.first(5).to_h }
      end

      def compute_pressure(acceptance_rate, driver_count, total_quotes)
        demand_factor = [total_quotes / 10.0, 3.0].min
        supply_factor = driver_count && driver_count > 0 ? [10.0 / driver_count, 3.0].min : 2.0
        rejection_factor = [(100.0 - acceptance_rate) / 30.0, 3.0].min

        ((demand_factor + supply_factor + rejection_factor) / 3.0 * 100).round(1)
      end

      def empty_dashboard
        { city_code: @city_code, lookback_hours: @lookback_hours, overall: { total_quotes: 0 },
          by_vehicle: [], by_time_band: [], hot_zones: [], generated_at: Time.current.iso8601 }
      end
    end
  end
end
