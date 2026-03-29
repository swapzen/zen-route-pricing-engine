# frozen_string_literal: true

class AddBackhaulProbabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :backhaul_probabilities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :zone, type: :bigint, null: false, foreign_key: true
      t.string :time_band, null: false
      t.float :return_probability, null: false, default: 0.5
      t.integer :avg_return_distance_m, default: 0
      t.integer :sample_size, default: 0

      t.timestamps
    end

    add_index :backhaul_probabilities, [:zone_id, :time_band], unique: true

    add_column :pricing_quotes, :backhaul_multiplier, :float, default: 1.0
    add_column :pricing_configs, :max_backhaul_premium, :float, default: 0.20
  end
end
