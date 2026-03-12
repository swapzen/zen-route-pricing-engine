# frozen_string_literal: true

class AddPerMinRateToPricingTables < ActiveRecord::Migration[8.0]
  def change
    add_column :pricing_configs, :per_min_rate_paise, :bigint, default: 0
    add_column :zone_vehicle_pricings, :per_min_rate_paise, :bigint, default: 0
    add_column :zone_vehicle_time_pricings, :per_min_rate_paise, :bigint, default: 0
    add_column :zone_pair_vehicle_pricings, :per_min_rate_paise, :bigint, default: 0
  end
end
