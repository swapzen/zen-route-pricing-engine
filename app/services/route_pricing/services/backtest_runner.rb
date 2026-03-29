# frozen_string_literal: true

module RoutePricing
  module Services
    class BacktestRunner
      MAX_DELTA_PCT = 25.0
      MEAN_DELTA_THRESHOLD = 10.0

      def initialize(backtest)
        @backtest = backtest
      end

      def run!
        @backtest.start!

        candidate_config = PricingConfig.find(@backtest.candidate_config_id)
        baseline_config = PricingConfig.find(@backtest.baseline_config_id)

        # Sample recent quotes for the same city + vehicle
        quotes = PricingQuote
                   .where(city_code: @backtest.city_code, vehicle_type: candidate_config.vehicle_type)
                   .where('created_at >= ?', 30.days.ago)
                   .order(created_at: :desc)
                   .limit(@backtest.sample_size || 100)

        if quotes.empty?
          @backtest.fail!('No quotes found for replay')
          return @backtest
        end

        replay_details = []
        deltas = []
        batch_size = 25

        quotes.each_with_index do |quote, idx|
          replay = replay_quote(quote, candidate_config, baseline_config)
          replay_details << replay
          deltas << replay[:delta_pct] if replay[:delta_pct]

          # Batch progress updates every 25 quotes to reduce DB writes
          if ((idx + 1) % batch_size).zero? || idx == quotes.size - 1
            @backtest.update!(completed_replays: replay_details.size)
          end
        end

        results = aggregate_results(deltas, replay_details, quotes)
        @backtest.complete!(results)
        @backtest
      rescue StandardError => e
        @backtest.fail!(e.message)
        @backtest
      end

      private

      def replay_quote(quote, candidate_config, baseline_config)
        breakdown = quote.breakdown_json || {}

        # Re-calculate with candidate config
        candidate_calc = PriceCalculator.new(config: candidate_config)
        candidate_result = candidate_calc.calculate(
          distance_m: quote.distance_m,
          duration_s: quote.duration_s,
          duration_in_traffic_s: quote.duration_s,
          pickup_lat: quote.pickup_raw_lat,
          pickup_lng: quote.pickup_raw_lng,
          drop_lat: quote.drop_raw_lat,
          drop_lng: quote.drop_raw_lng,
          item_value_paise: nil,
          quote_time: quote.created_at
        )

        candidate_price = candidate_result[:final_price_paise]
        baseline_price = quote.price_paise
        actual_price = quote.pricing_actual&.actual_price_paise

        delta = candidate_price - baseline_price
        delta_pct = baseline_price > 0 ? ((delta.to_f / baseline_price) * 100).round(2) : 0

        result = {
          quote_id: quote.id,
          baseline_price: baseline_price,
          candidate_price: candidate_price,
          delta_paise: delta,
          delta_pct: delta_pct
        }

        if actual_price
          candidate_margin = candidate_price - actual_price
          baseline_margin = baseline_price - actual_price
          result[:actual_price] = actual_price
          result[:candidate_margin_paise] = candidate_margin
          result[:baseline_margin_paise] = baseline_margin
        end

        result
      end

      def aggregate_results(deltas, replay_details, quotes)
        return { sample_count: 0, pass: false, error: 'No valid deltas' } if deltas.empty?

        sorted = deltas.sort
        mean = (deltas.sum / deltas.size).round(2)
        median = sorted[sorted.size / 2].round(2)
        p95_idx = (sorted.size * 0.95).ceil - 1
        p95 = sorted[[p95_idx, 0].max].round(2)

        # Margin impact (only if actuals exist)
        with_actuals = replay_details.select { |r| r[:actual_price] }
        margin_impact = if with_actuals.any?
                          candidate_margins = with_actuals.map { |r| r[:candidate_margin_paise] }
                          baseline_margins = with_actuals.map { |r| r[:baseline_margin_paise] }
                          avg_candidate = candidate_margins.sum.to_f / candidate_margins.size
                          avg_baseline = baseline_margins.sum.to_f / baseline_margins.size
                          avg_baseline != 0 ? (((avg_candidate - avg_baseline) / avg_baseline.abs) * 100).round(2) : 0
                        end

        max_abs_delta = deltas.map(&:abs).max || 0
        pass = mean.abs < MEAN_DELTA_THRESHOLD && max_abs_delta < MAX_DELTA_PCT

        {
          sample_count: deltas.size,
          mean_price_delta_pct: mean,
          median_delta: median,
          p95_delta: p95,
          max_abs_delta: max_abs_delta.round(2),
          margin_impact_pct: margin_impact,
          actuals_available: with_actuals.size,
          pass: pass
        }
      end
    end
  end
end
