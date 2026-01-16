# frozen_string_literal: true

class CreatePricingZoneMultipliers < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_zone_multipliers, id: :uuid do |t|
      t.string :zone_code, null: false
      t.string :zone_name
      t.string :city_code, default: 'hyd'
      t.decimal :lat_min, precision: 10, scale: 6
      t.decimal :lat_max, precision: 10, scale: 6
      t.decimal :lng_min, precision: 10, scale: 6
      t.decimal :lng_max, precision: 10, scale: 6
      t.decimal :multiplier, precision: 4, scale: 2, default: 1.0
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :pricing_zone_multipliers, [:city_code, :zone_code], unique: true
    add_index :pricing_zone_multipliers, [:lat_min, :lat_max, :lng_min, :lng_max], 
              name: 'idx_zone_coords'
  end
end
