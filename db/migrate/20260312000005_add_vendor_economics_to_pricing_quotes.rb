# frozen_string_literal: true

class AddVendorEconomicsToPricingQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_quotes, :vendor_predicted_paise, :bigint
    add_column :pricing_quotes, :vendor_code, :string
    add_column :pricing_quotes, :margin_paise, :bigint
    add_column :pricing_quotes, :margin_pct, :decimal, precision: 6, scale: 2
    add_column :pricing_quotes, :vendor_confidence, :string, default: 'none'
  end
end
