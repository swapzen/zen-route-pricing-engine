# frozen_string_literal: true

class AddH3IndexR8ToZoneH3Mappings < ActiveRecord::Migration[8.0]
  def change
    add_column :zone_h3_mappings, :h3_index_r8, :string
    add_index :zone_h3_mappings, [:city_code, :h3_index_r8], name: "idx_zone_h3_mappings_r8_city"
  end
end
