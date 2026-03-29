# frozen_string_literal: true

class CreatePricingQuoteDecisions < ActiveRecord::Migration[8.0]
  def change
    # Table already exists from a prior migration — add drift-tracking columns
    unless column_exists?(:pricing_quote_decisions, :quoted_price_paise)
      add_column :pricing_quote_decisions, :time_band, :string
      add_column :pricing_quote_decisions, :pickup_zone_code, :string
      add_column :pricing_quote_decisions, :drop_zone_code, :string
      add_column :pricing_quote_decisions, :quoted_price_paise, :integer
      add_column :pricing_quote_decisions, :actual_price_paise, :integer
      add_column :pricing_quote_decisions, :variance_paise, :integer
      add_column :pricing_quote_decisions, :variance_pct, :float
      add_column :pricing_quote_decisions, :pricing_tier, :string
      add_column :pricing_quote_decisions, :distance_km, :float
      add_column :pricing_quote_decisions, :config_version, :string
      add_column :pricing_quote_decisions, :within_threshold, :boolean, default: true
    end

    unless index_exists?(:pricing_quote_decisions, :within_threshold)
      add_index :pricing_quote_decisions, :within_threshold
    end
  end
end
