# frozen_string_literal: true

class CreateZoneH3Mappings < ActiveRecord::Migration[8.0]
  def change
    create_table :zone_h3_mappings, id: :uuid do |t|
      t.string :h3_index_r7, null: false
      t.string :h3_index_r9
      t.bigint :zone_id, null: false
      t.string :city_code, null: false
      t.boolean :is_boundary, default: false

      t.timestamps
    end

    add_foreign_key :zone_h3_mappings, :zones
    add_index :zone_h3_mappings, [:h3_index_r7, :zone_id], unique: true,
              name: 'idx_zone_h3_mappings_r7_zone'
    add_index :zone_h3_mappings, [:h3_index_r7, :city_code],
              name: 'idx_zone_h3_mappings_r7_city'
    add_index :zone_h3_mappings, [:h3_index_r9, :city_code],
              name: 'idx_zone_h3_mappings_r9_city'
  end
end
