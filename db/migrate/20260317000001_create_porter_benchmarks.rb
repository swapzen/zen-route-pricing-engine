# frozen_string_literal: true

class CreatePorterBenchmarks < ActiveRecord::Migration[8.0]
  def change
    create_table :porter_benchmarks, id: :uuid do |t|
      t.string  :city_code, null: false, default: 'hyd'
      t.string  :route_key, null: false
      t.string  :pickup_address, null: false
      t.string  :drop_address, null: false
      t.decimal :pickup_lat, precision: 10, scale: 6
      t.decimal :pickup_lng, precision: 10, scale: 6
      t.decimal :drop_lat, precision: 10, scale: 6
      t.decimal :drop_lng, precision: 10, scale: 6
      t.string  :vehicle_type, null: false
      t.string  :time_band, null: false
      t.integer :porter_price_inr
      t.integer :our_price_inr
      t.integer :distance_m
      t.float   :delta_pct
      t.string  :status, default: 'entered'
      t.string  :entered_by
      t.timestamps
    end

    add_index :porter_benchmarks, [:route_key, :vehicle_type, :time_band],
              unique: true, name: 'idx_porter_bench_route_vt_tb'
    add_index :porter_benchmarks, [:city_code, :time_band]
  end
end
