class AddTimeBandToZonePairVehiclePricings < ActiveRecord::Migration[8.0]
  def up
    # Add time_band column (nullable for backward compatibility)
    add_column :zone_pair_vehicle_pricings, :time_band, :string
    
    # Drop old unique index
    remove_index :zone_pair_vehicle_pricings, 
                 name: 'idx_zpvp_routing'
    
    # Add new unique index that includes time_band
    # Allows multiple records per route with different time bands
    # NULL time_band is treated as a distinct value (for backward compatibility)
    add_index :zone_pair_vehicle_pricings,
              [:city_code, :from_zone_id, :to_zone_id, :vehicle_type, :time_band],
              unique: true,
              name: 'idx_zpvp_routing_with_time_band'
  end

  def down
    # Remove new index
    remove_index :zone_pair_vehicle_pricings,
                 name: 'idx_zpvp_routing_with_time_band'
    
    # Restore old unique index
    add_index :zone_pair_vehicle_pricings,
              [:city_code, :from_zone_id, :to_zone_id, :vehicle_type],
              unique: true,
              name: 'idx_zpvp_routing'
    
    # Remove time_band column
    remove_column :zone_pair_vehicle_pricings, :time_band
  end
end
