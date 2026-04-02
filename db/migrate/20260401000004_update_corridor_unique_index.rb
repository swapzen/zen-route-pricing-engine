class UpdateCorridorUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    # Remove old flat index that assumed one record per (zone-pair, vehicle, time_band)
    remove_index :zone_pair_vehicle_pricings, name: 'idx_zpvp_routing_with_time_band', if_exists: true

    # Partial unique index for base records: one active base per (zone-pair, vehicle)
    execute <<~SQL
      CREATE UNIQUE INDEX idx_zpvp_base_unique
      ON zone_pair_vehicle_pricings (city_code, from_zone_id, to_zone_id, vehicle_type)
      WHERE time_band IS NULL AND active = true
    SQL

    # Non-unique lookup index for general queries (includes legacy flat records)
    add_index :zone_pair_vehicle_pricings,
              [:city_code, :from_zone_id, :to_zone_id, :vehicle_type, :time_band],
              name: 'idx_zpvp_routing_lookup'
  end

  def down
    remove_index :zone_pair_vehicle_pricings, name: 'idx_zpvp_base_unique', if_exists: true
    remove_index :zone_pair_vehicle_pricings, name: 'idx_zpvp_routing_lookup', if_exists: true

    # Restore original index
    add_index :zone_pair_vehicle_pricings,
              [:city_code, :from_zone_id, :to_zone_id, :vehicle_type, :time_band],
              unique: true,
              name: 'idx_zpvp_routing_with_time_band'
  end
end
