class CreateZonePairVehicleTimePricings < ActiveRecord::Migration[8.0]
  def change
    create_table :zone_pair_vehicle_time_pricings, id: :uuid do |t|
      t.references :zone_pair_vehicle_pricing, null: false, foreign_key: true, type: :uuid
      t.string :time_band, null: false
      t.integer :base_fare_paise, null: false
      t.integer :per_km_rate_paise, null: false
      t.integer :min_fare_paise, null: false
      t.integer :per_min_rate_paise, default: 0
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :zone_pair_vehicle_time_pricings,
              [:zone_pair_vehicle_pricing_id, :time_band],
              unique: true,
              name: 'idx_zpvtp_pricing_time_band'
  end
end
