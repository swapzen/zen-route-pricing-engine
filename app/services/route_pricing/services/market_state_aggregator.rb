# frozen_string_literal: true

module RoutePricing
  module Services
    class MarketStateAggregator
      def initialize(city_code:, lookback_hours: 24)
        @city_code = city_code
        @lookback_hours = lookback_hours
      end

      def dashboard
        outcomes = base_scope

        return empty_dashboard if outcomes.empty?

        {
          city_code: @city_code,
          lookback_hours: @lookback_hours,
          overall: overall_metrics(outcomes),
          by_vehicle: vehicle_breakdown(outcomes),
          by_time_band: time_band_breakdown(outcomes),
          hot_zones: hot_zones(outcomes),
          generated_at: Time.current.iso8601
        }
      end

      def zone_health
        outcomes = base_scope
        return [] if outcomes.empty?

        grouped = outcomes.group_by(&:pickup_zone_code).reject { |k, _| k.blank? }

        grouped.map do |zone_code, group|
          total = group.size
          accepted = group.count { |o| o.outcome == 'accepted' }
          rejected = group.count { |o| o.outcome == 'rejected' }
          avg_price = group.map(&:quoted_price_paise).compact.sum.to_f / total

          {
            zone_code: zone_code,
            total_quotes: total,
            acceptance_rate: (accepted.to_f / total * 100).round(2),
            rejection_rate: (rejected.to_f / total * 100).round(2),
            avg_quoted_price_paise: avg_price.round,
            avg_response_time_s: group.map(&:response_time_seconds).compact.then { |a| a.any? ? (a.sum.to_f / a.size).round(1) : nil },
            top_rejection_reasons: rejection_reasons(group)
          }
        end.sort_by { |z| z[:acceptance_rate] }
      end

      def pressure_map
        outcomes = base_scope.where.not(h3_index_r7: nil)
        return [] if outcomes.empty?

        grouped = outcomes.group_by { |o| [o.h3_index_r7, o.time_band] }

        grouped.map do |(hex, time_band), group|
          total = group.size
          accepted = group.count { |o| o.outcome == 'accepted' }
          rejected = group.count { |o| o.outcome == 'rejected' }
          acceptance_rate = total > 0 ? (accepted.to_f / total * 100).round(2) : 0

          supply = H3SupplyDensity.for_cell(hex, @city_code, time_band || 'morning').first

          {
            h3_index_r7: hex,
            time_band: time_band,
            total_quotes: total,
            acceptance_rate: acceptance_rate,
            rejection_rate: total > 0 ? (rejected.to_f / total * 100).round(2) : 0,
            supply_density: supply&.estimated_driver_count,
            pressure_score: compute_pressure(acceptance_rate, supply&.estimated_driver_count, total)
          }
        end.sort_by { |p| -p[:pressure_score] }
      end

      private

      def base_scope
        PricingOutcome.for_city(@city_code).recent(@lookback_hours)
      end

      def overall_metrics(outcomes)
        total = outcomes.count
        accepted = outcomes.select { |o| o.outcome == 'accepted' }.size
        rejected = outcomes.select { |o| o.outcome == 'rejected' }.size
        response_times = outcomes.map(&:response_time_seconds).compact

        {
          total_quotes: total,
          acceptance_rate: (accepted.to_f / total * 100).round(2),
          rejection_rate: (rejected.to_f / total * 100).round(2),
          avg_response_time_s: response_times.any? ? (response_times.sum.to_f / response_times.size).round(1) : nil,
          avg_quoted_price_paise: outcomes.map(&:quoted_price_paise).compact.then { |a| a.any? ? (a.sum.to_f / a.size).round : nil }
        }
      end

      def vehicle_breakdown(outcomes)
        outcomes.group_by(&:vehicle_type).reject { |k, _| k.blank? }.map do |vt, group|
          total = group.size
          accepted = group.count { |o| o.outcome == 'accepted' }
          avg_price = group.map(&:quoted_price_paise).compact

          {
            vehicle_type: vt,
            total_quotes: total,
            acceptance_rate: (accepted.to_f / total * 100).round(2),
            avg_price_paise: avg_price.any? ? (avg_price.sum.to_f / avg_price.size).round : nil
          }
        end
      end

      def time_band_breakdown(outcomes)
        outcomes.group_by(&:time_band).reject { |k, _| k.blank? }.map do |tb, group|
          total = group.size
          accepted = group.count { |o| o.outcome == 'accepted' }

          {
            time_band: tb,
            total_quotes: total,
            acceptance_rate: (accepted.to_f / total * 100).round(2)
          }
        end
      end

      def hot_zones(outcomes)
        zone_groups = outcomes.group_by(&:pickup_zone_code).reject { |k, _| k.blank? }

        zone_groups.filter_map do |zone_code, group|
          total = group.size
          next nil if total < 3

          rejected = group.count { |o| o.outcome == 'rejected' }
          rejection_rate = (rejected.to_f / total * 100).round(2)

          next nil if rejection_rate < 30

          {
            zone_code: zone_code,
            total_quotes: total,
            rejection_rate: rejection_rate,
            top_reasons: rejection_reasons(group)
          }
        end.sort_by { |z| -z[:rejection_rate] }.first(10)
      end

      def rejection_reasons(group)
        group
          .select { |o| o.outcome == 'rejected' && o.rejection_reason.present? }
          .group_by(&:rejection_reason)
          .transform_values(&:size)
          .sort_by { |_, v| -v }
          .first(5)
          .to_h
      end

      def compute_pressure(acceptance_rate, driver_count, total_quotes)
        # Higher pressure = low acceptance + low supply + high demand
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
