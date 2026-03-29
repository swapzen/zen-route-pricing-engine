# frozen_string_literal: true

class AddWeatherSupport < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_configs, :weather_multipliers, :jsonb, default: nil
    add_column :pricing_quotes, :weather_condition, :string
    add_column :pricing_quotes, :weather_multiplier, :float, default: 1.0
  end
end
