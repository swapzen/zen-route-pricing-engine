# frozen_string_literal: true

class CreatePricingSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_snapshots do |t|
      t.string :city_code, null: false
      t.string :name, null: false
      t.text :description
      t.jsonb :snapshot_data, null: false, default: {}
      t.string :created_by
      t.timestamps
    end

    add_index :pricing_snapshots, :city_code
    add_index :pricing_snapshots, :created_at
  end
end
