# frozen_string_literal: true

class AddAdvancedPricingFeatures < ActiveRecord::Migration[8.0]
  def change
    # PricingConfig additions
    add_column :pricing_configs, :scheduled_discount_pct, :decimal, precision: 5, scale: 2, default: 0.0
    add_column :pricing_configs, :scheduled_threshold_hours, :integer, default: 2
    add_column :pricing_configs, :return_trip_discount_pct, :decimal, precision: 5, scale: 2, default: 10.0
    add_column :pricing_configs, :weight_multiplier_tiers, :jsonb, default: [
      { "max_kg" => 15, "mult" => 1.0 },
      { "max_kg" => 50, "mult" => 1.1 },
      { "max_kg" => 200, "mult" => 1.2 },
      { "max_kg" => nil, "mult" => 1.4 }
    ]

    # PricingQuote additions
    add_column :pricing_quotes, :scheduled_for, :datetime
    add_column :pricing_quotes, :is_scheduled, :boolean, default: false
    add_column :pricing_quotes, :linked_quote_id, :uuid
    add_column :pricing_quotes, :trip_leg, :string
    add_column :pricing_quotes, :weight_kg, :decimal, precision: 8, scale: 2

    add_index :pricing_quotes, :linked_quote_id
  end
end
