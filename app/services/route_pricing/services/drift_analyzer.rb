# frozen_string_literal: true

module RoutePricing
  module Services
    class DriftAnalyzer
      DEFAULT_LOOKBACK_DAYS = 7
      DEFAULT_THRESHOLD_PCT = 15.0

      def initialize(city_code:, lookback_days: DEFAULT_LOOKBACK_DAYS, threshold_pct: DEFAULT_THRESHOLD_PCT)
        @city_code = city_code
        @lookback_days = lookback_days
        @threshold_pct = threshold_pct
      end

      def analyze
        decisions = PricingQuoteDecision
                      .for_city(@city_code)
                      .recent(@lookback_days)

        return empty_report if decisions.empty?

        corridors = group_and_analyze(decisions)
        alert_level = determine_alert_level(corridors)

        {
          city_code: @city_code,
          lookback_days: @lookback_days,
          threshold_pct: @threshold_pct,
          total_decisions: decisions.count,
          drifted_count: corridors.count { |c| c[:drifted] },
          corridors: corridors.sort_by { |c| -c[:mean_variance_pct].abs },
          alert_level: alert_level,
          recommendations: build_recommendations(corridors, alert_level),
          analyzed_at: Time.current.iso8601
        }
      end

      def summary
        decisions = PricingQuoteDecision.for_city(@city_code).recent(@lookback_days)
        return empty_summary if decisions.empty?

        total = decisions.count
        drifted = decisions.drifted.count
        drifted_pct = (drifted.to_f / total * 100).round(2)

        worst = decisions.order(Arel.sql('ABS(variance_pct) DESC')).limit(5)

        {
          city_code: @city_code,
          total_decisions: total,
          drifted_count: drifted,
          drifted_pct: drifted_pct,
          avg_variance_pct: decisions.average(:variance_pct)&.round(2) || 0,
          worst_offenders: worst.map { |d| format_decision(d) },
          trend: compute_trend(decisions),
          analyzed_at: Time.current.iso8601
        }
      end

      private

      def group_and_analyze(decisions)
        rows = decisions
          .where.not(variance_pct: nil)
          .group(:vehicle_type, :time_band, :pickup_zone_code, :drop_zone_code)
          .select(
            'vehicle_type', 'time_band', 'pickup_zone_code', 'drop_zone_code',
            'COUNT(*) AS sample_count',
            'AVG(variance_pct) AS mean_variance',
            'MIN(variance_pct) AS min_variance',
            'MAX(variance_pct) AS max_variance'
          )

        rows.filter_map do |r|
          mean = r.mean_variance&.round(2).to_f
          {
            vehicle_type: r.vehicle_type,
            time_band: r.time_band,
            pickup_zone: r.pickup_zone_code,
            drop_zone: r.drop_zone_code,
            sample_count: r.sample_count.to_i,
            mean_variance_pct: mean,
            p95_variance_pct: r.max_variance&.round(2),
            min_variance_pct: r.min_variance&.round(2),
            max_variance_pct: r.max_variance&.round(2),
            drifted: mean.abs > @threshold_pct
          }
        end
      end

      def determine_alert_level(corridors)
        return 'green' if corridors.empty?

        drifted_pct = corridors.count { |c| c[:drifted] }.to_f / corridors.size * 100

        if drifted_pct > 30
          'red'
        elsif drifted_pct > 10
          'yellow'
        else
          'green'
        end
      end

      def build_recommendations(corridors, alert_level)
        recs = []

        drifted = corridors.select { |c| c[:drifted] }
        if drifted.any?
          recs << "#{drifted.size} corridor(s) exceed #{@threshold_pct}% drift threshold"
        end

        underpriced = drifted.select { |c| c[:mean_variance_pct] > 0 }
        if underpriced.any?
          recs << "#{underpriced.size} corridor(s) are underpriced (actual > quoted) — consider rate increase"
        end

        overpriced = drifted.select { |c| c[:mean_variance_pct] < 0 }
        if overpriced.any?
          recs << "#{overpriced.size} corridor(s) are overpriced (actual < quoted) — consider rate decrease"
        end

        recs << 'Recalibration recommended' if alert_level == 'red'

        recs
      end

      def compute_trend(decisions)
        recent_half = decisions.where('created_at >= ?', (@lookback_days / 2.0).days.ago)
        older_half = decisions.where('created_at < ?', (@lookback_days / 2.0).days.ago)

        recent_avg = recent_half.average(:variance_pct)&.to_f || 0
        older_avg = older_half.average(:variance_pct)&.to_f || 0

        if (recent_avg - older_avg).abs < 2
          'stable'
        elsif recent_avg.abs > older_avg.abs
          'worsening'
        else
          'improving'
        end
      end

      def format_decision(d)
        {
          vehicle_type: d.vehicle_type,
          time_band: d.time_band,
          pickup_zone: d.pickup_zone_code,
          drop_zone: d.drop_zone_code,
          variance_pct: d.variance_pct,
          quoted: d.quoted_price_paise,
          actual: d.actual_price_paise
        }
      end

      def empty_report
        { city_code: @city_code, total_decisions: 0, corridors: [], alert_level: 'green',
          recommendations: ['No data available for analysis'], analyzed_at: Time.current.iso8601 }
      end

      def empty_summary
        { city_code: @city_code, total_decisions: 0, drifted_count: 0, drifted_pct: 0,
          avg_variance_pct: 0, worst_offenders: [], trend: 'stable', analyzed_at: Time.current.iso8601 }
      end
    end
  end
end
