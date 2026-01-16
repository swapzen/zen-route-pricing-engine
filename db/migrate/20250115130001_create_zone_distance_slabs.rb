# frozen_string_literal: true

class CreateZoneDistanceSlabs < ActiveRecord::Migration[8.0]
  def change
    create_table :zone_distance_slabs, id: :uuid do |t|
      t.string :city_code, null: false
      t.references :zone, null: false, foreign_key: true, type: :bigint
      t.string :vehicle_type, null: false
      
      # Slab definition (same structure as pricing_distance_slabs)
      t.integer :min_distance_m, null: false, default: 0
      t.integer :max_distance_m  # nil = infinity (unlimited)
      t.integer :per_km_rate_paise, null: false
      
      # Optional: flat fare for this slab (e.g., minimum for micro routes)
      t.integer :flat_fare_paise
      
      t.integer :priority, default: 10
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    # Unique constraint: one slab per zone/vehicle/distance range
    add_index :zone_distance_slabs, 
              [:city_code, :zone_id, :vehicle_type, :min_distance_m], 
              unique: true, 
              name: 'idx_zone_slabs_unique'
    
    # For fast lookups
    add_index :zone_distance_slabs, [:zone_id, :vehicle_type, :active]
    add_index :zone_distance_slabs, [:city_code, :active]
  end
end
