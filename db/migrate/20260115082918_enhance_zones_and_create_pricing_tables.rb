class EnhanceZonesAndCreatePricingTables < ActiveRecord::Migration[7.0]
  def change
    # 1. Enhance existing Zones table
    change_table :zones do |t|
      t.string :zone_code
      t.string :zone_type # tech_corridor, cbd, etc.
      
      # Geospatial definition
      t.decimal :lat_min, precision: 10, scale: 6
      t.decimal :lat_max, precision: 10, scale: 6
      t.decimal :lng_min, precision: 10, scale: 6
      t.decimal :lng_max, precision: 10, scale: 6
      
      t.integer :priority, default: 0
      t.jsonb :metadata, default: {}
    end
    
    # Ensure uniqueness, using 'city' column which already exists
    add_index :zones, [:city, :zone_code], unique: true
    add_index :zones, [:city, :zone_type]

    # 2. Zone Vehicle Pricings
    create_table :zone_vehicle_pricings, id: :uuid do |t|
      t.references :zone, null: false, foreign_key: true
      t.string :city_code, null: false
      t.string :vehicle_type, null: false
      
      t.integer :base_fare_paise, null: false
      t.integer :min_fare_paise, null: false
      t.integer :base_distance_m, null: false
      t.integer :per_km_rate_paise, null: false
      
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :zone_vehicle_pricings, [:city_code, :zone_id, :vehicle_type], unique: true, name: 'idx_zvp_lookup'

    # 3. Zone Pair Vehicle Pricings
    create_table :zone_pair_vehicle_pricings, id: :uuid do |t|
      t.string :city_code, null: false
      # References to bigint ID on zones table
      t.references :from_zone, null: false, foreign_key: { to_table: :zones }
      t.references :to_zone, null: false, foreign_key: { to_table: :zones }
      t.string :vehicle_type, null: false
      
      t.integer :base_fare_paise
      t.integer :min_fare_paise
      t.integer :per_km_rate_paise
      
      t.string :corridor_type
      t.boolean :directional, default: true
      
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :zone_pair_vehicle_pricings, 
              [:city_code, :from_zone_id, :to_zone_id, :vehicle_type], 
              unique: true, 
              name: 'idx_zpvp_routing'
  end
end
