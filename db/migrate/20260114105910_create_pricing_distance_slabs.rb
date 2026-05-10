# frozen_string_literal: true

class CreatePricingDistanceSlabs < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:pricing_distance_slabs)
      create_table :pricing_distance_slabs, id: :uuid do |t|
        t.references :pricing_config, null: false, type: :uuid, foreign_key: true
        t.integer :min_distance_m, null: false, default: 0
        t.integer :max_distance_m # NULL = infinity (open-ended slab)
        t.integer :per_km_rate_paise, null: false
        t.timestamps
      end
    end

    add_index :pricing_distance_slabs,
              [:pricing_config_id, :min_distance_m],
              unique: true,
              name: "idx_slabs_config_min_distance",
              if_not_exists: true
  end

  def down
    drop_table :pricing_distance_slabs, if_exists: true
  end
end
