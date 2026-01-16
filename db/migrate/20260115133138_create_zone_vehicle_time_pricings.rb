class CreateZoneVehicleTimePricings < ActiveRecord::Migration[7.0]
  def change
    create_table :zone_vehicle_time_pricings, id: :uuid do |t|
      t.references :zone_vehicle_pricing, type: :uuid, null: false, foreign_key: true
      t.string :time_band, null: false # morning, afternoon, evening
      
      # Pricing components for this time slot
      t.integer :base_fare_paise, null: false
      t.integer :min_fare_paise, null: false
      t.integer :per_km_rate_paise, null: false
      
      t.boolean :active, default: true
      t.timestamps
    end

    # Composite index: lookup by zone vehicle pricing + time band
    add_index :zone_vehicle_time_pricings, 
              [:zone_vehicle_pricing_id, :time_band], 
              unique: true, 
              name: 'idx_zvtp_pricing_time'
  end
end
