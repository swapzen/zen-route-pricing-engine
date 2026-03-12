# frozen_string_literal: true

class AddDeadKmConfigToPricingConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_configs, :free_pickup_radius_m, :bigint, default: 0
    add_column :pricing_configs, :dead_km_per_km_rate_paise, :bigint, default: 0
    add_column :pricing_configs, :dead_km_enabled, :boolean, default: false
  end
end
