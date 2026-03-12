# frozen_string_literal: true

class CreateH3SupplyDensity < ActiveRecord::Migration[8.0]
  def change
    create_table :h3_supply_density, id: :uuid do |t|
      t.string :h3_index_r7, null: false
      t.string :city_code, null: false
      t.string :time_band, null: false
      t.integer :avg_pickup_distance_m, default: 3000
      t.integer :estimated_driver_count, default: 0
      t.boolean :zone_type_default, default: true

      t.timestamps
    end

    add_index :h3_supply_density, [:h3_index_r7, :city_code, :time_band],
              unique: true, name: 'idx_h3_supply_density_unique'
  end
end
