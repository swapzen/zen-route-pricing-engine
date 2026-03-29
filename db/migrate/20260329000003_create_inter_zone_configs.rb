# frozen_string_literal: true

class CreateInterZoneConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :inter_zone_configs do |t|
      t.string :city_code, null: false
      t.float :origin_weight, null: false, default: 0.6
      t.float :destination_weight, null: false, default: 0.4
      t.jsonb :type_adjustments, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :inter_zone_configs, [:city_code, :active]
  end
end
