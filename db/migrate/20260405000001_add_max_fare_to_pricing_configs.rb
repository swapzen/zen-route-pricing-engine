# frozen_string_literal: true

class AddMaxFareToPricingConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_configs, :max_fare_paise, :integer
    add_column :pricing_configs, :high_value_ratio_threshold, :decimal, precision: 3, scale: 2, default: 0.40
  end
end
