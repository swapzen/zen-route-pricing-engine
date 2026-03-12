# frozen_string_literal: true

class EnhancePricingActuals < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_actuals, :actual_vendor_code, :string
    add_column :pricing_actuals, :actual_breakdown_json, :jsonb, default: {}
    add_column :pricing_actuals, :predicted_vendor_paise, :bigint
    add_column :pricing_actuals, :prediction_variance_paise, :bigint
    add_column :pricing_actuals, :prediction_variance_pct, :decimal, precision: 6, scale: 2
  end
end
