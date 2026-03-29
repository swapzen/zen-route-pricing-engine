# frozen_string_literal: true

class AddMinFareWaitingCancellation < ActiveRecord::Migration[8.0]
  def change
    # Zone-adjusted minimum fares (Phase 4)
    add_column :zones, :min_fare_overrides, :jsonb, default: nil

    # Cancellation risk (Phase 6)
    add_column :zones, :cancellation_rate_pct, :float, default: nil

    # Waiting/loading charges (Phase 5)
    add_column :pricing_configs, :waiting_per_min_rate_paise, :bigint, default: 0
    add_column :pricing_configs, :free_waiting_minutes, :integer, default: 10

    # Quote-level tracking
    add_column :pricing_quotes, :estimated_waiting_charge_paise, :bigint, default: 0
    add_column :pricing_quotes, :cancellation_risk_multiplier, :float, default: 1.0
  end
end
