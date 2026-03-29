# frozen_string_literal: true

module RoutePricing
  module Services
    class CandidatePriceOptimizer
      DEFAULT_TARGET_MARGIN = 0.15 # 15%

      def initialize(model_config:)
        @model_config = model_config
        @target_margin = (model_config.parameters['target_margin'] || DEFAULT_TARGET_MARGIN).to_f
      end

      # Score a quote in shadow mode (does NOT affect live price)
      def score(quote_id:, deterministic_price_paise:, city_code:, vehicle_type:, time_band: nil,
                pickup_zone: nil, drop_zone: nil, distance_km: nil)
        # 1. Look up historical decisions for similar corridor
        decisions = PricingQuoteDecision
                      .for_city(city_code)
                      .for_vehicle(vehicle_type)
                      .recent(30)

        decisions = decisions.for_time_band(time_band) if time_band.present?
        decisions = decisions.where(pickup_zone_code: pickup_zone) if pickup_zone.present?
        decisions = decisions.where(drop_zone_code: drop_zone) if drop_zone.present?

        # 2. Compute corridor stats
        actuals = decisions.where.not(actual_price_paise: nil)
        outcomes = PricingOutcome.for_city(city_code).recent(168) # 7 days in hours

        features = {
          city_code: city_code,
          vehicle_type: vehicle_type,
          time_band: time_band,
          pickup_zone: pickup_zone,
          drop_zone: drop_zone,
          distance_km: distance_km,
          historical_decisions: decisions.count,
          historical_actuals: actuals.count
        }

        if actuals.count < 5
          # Not enough data — suggest deterministic price
          return log_score(
            quote_id: quote_id,
            deterministic: deterministic_price_paise,
            suggested: deterministic_price_paise,
            acceptance_pct: nil,
            margin_pct: nil,
            features: features
          )
        end

        # 3. Calculate suggested price
        avg_actual = actuals.average(:actual_price_paise).to_f
        suggested = [avg_actual * (1 + @target_margin), deterministic_price_paise * 0.8].max.round

        # 4. Estimate acceptance from historical outcomes
        acceptance_rate = if outcomes.any?
                           scoped = outcomes.where(vehicle_type: vehicle_type)
                           scoped = scoped.where(pickup_zone_code: pickup_zone) if pickup_zone.present?
                           total = scoped.count
                           total > 0 ? (scoped.accepted.count.to_f / total * 100).round(2) : nil
                         end

        # 5. Estimate margin
        margin_pct = avg_actual > 0 ? ((suggested - avg_actual) / avg_actual * 100).round(2) : nil

        features[:avg_actual_cost] = avg_actual.round
        features[:acceptance_rate] = acceptance_rate

        log_score(
          quote_id: quote_id,
          deterministic: deterministic_price_paise,
          suggested: suggested,
          acceptance_pct: acceptance_rate,
          margin_pct: margin_pct,
          features: features
        )
      end

      private

      def log_score(quote_id:, deterministic:, suggested:, acceptance_pct:, margin_pct:, features:)
        score = PricingModelScore.create!(
          pricing_quote_id: quote_id,
          model_version: @model_config.model_version,
          city_code: features[:city_code],
          vehicle_type: features[:vehicle_type],
          deterministic_price_paise: deterministic,
          model_suggested_paise: suggested,
          expected_acceptance_pct: acceptance_pct,
          expected_margin_pct: margin_pct,
          features: features,
          model_metadata: { algorithm_name: @model_config.algorithm_name, mode: @model_config.mode }
        )

        {
          score_id: score.id,
          deterministic_price: deterministic,
          model_suggested_price: suggested,
          delta_paise: suggested - deterministic,
          delta_pct: deterministic > 0 ? ((suggested - deterministic).to_f / deterministic * 100).round(2) : 0,
          expected_acceptance_pct: acceptance_pct,
          expected_margin_pct: margin_pct
        }
      end
    end
  end
end
