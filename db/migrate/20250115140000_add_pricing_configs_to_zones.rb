# frozen_string_literal: true

# Industry-Standard Pricing Configurations at Zone Level
# Based on Cogoport/ShipX patterns:
# - Fuel Surcharge (FSC) - % of fare, configurable per zone
# - Zone Multiplier (SLS) - Special Location Surcharge multiplier
# - ODA flag - Out of Delivery Area for remote zones
# - Special Location Surcharge - Flat fee for premium locations
class AddPricingConfigsToZones < ActiveRecord::Migration[7.1]
  def change
    # Zone-level pricing configuration
    add_column :zones, :fuel_surcharge_pct, :decimal, precision: 5, scale: 2, default: 0.0 unless column_exists?(:zones, :fuel_surcharge_pct)
    add_column :zones, :zone_multiplier, :decimal, precision: 5, scale: 3, default: 1.0 unless column_exists?(:zones, :zone_multiplier)
    add_column :zones, :is_oda, :boolean, default: false unless column_exists?(:zones, :is_oda)
    add_column :zones, :special_location_surcharge_paise, :integer, default: 0 unless column_exists?(:zones, :special_location_surcharge_paise)
    
    # ODA surcharge multiplier (used when both pickup & drop are ODA)
    add_column :zones, :oda_surcharge_pct, :decimal, precision: 5, scale: 2, default: 5.0 unless column_exists?(:zones, :oda_surcharge_pct)
    
    # Index for quick lookups
    add_index :zones, :is_oda unless index_exists?(:zones, :is_oda)
    add_index :zones, :zone_type unless index_exists?(:zones, :zone_type)
  end
end
