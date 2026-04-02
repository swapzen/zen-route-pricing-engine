class MigrateCorridorDataToTwoTier < ActiveRecord::Migration[8.0]
  def up
    # Group all active flat corridor records by (city_code, from_zone_id, to_zone_id, vehicle_type)
    groups = execute(<<~SQL).to_a
      SELECT DISTINCT city_code, from_zone_id, to_zone_id, vehicle_type
      FROM zone_pair_vehicle_pricings
      WHERE active = true AND time_band IS NOT NULL
    SQL

    base_created = 0
    overrides_created = 0
    flat_deactivated = 0

    groups.each do |group|
      city_code = group['city_code']
      from_zone_id = group['from_zone_id']
      to_zone_id = group['to_zone_id']
      vehicle_type = group['vehicle_type']

      records = execute(<<~SQL).to_a
        SELECT * FROM zone_pair_vehicle_pricings
        WHERE city_code = '#{city_code}'
          AND from_zone_id = '#{from_zone_id}'
          AND to_zone_id = '#{to_zone_id}'
          AND vehicle_type = '#{vehicle_type}'
          AND active = true
          AND time_band IS NOT NULL
        ORDER BY time_band
      SQL

      next if records.empty?

      # Pick morning_rush as base (Porter-calibrated, 1.0x multiplier)
      base_record = records.find { |r| r['time_band'] == 'morning_rush' } || records.first

      # Check if a base record (time_band: nil) already exists for this group
      existing_base = execute(<<~SQL).to_a
        SELECT id FROM zone_pair_vehicle_pricings
        WHERE city_code = '#{city_code}'
          AND from_zone_id = '#{from_zone_id}'
          AND to_zone_id = '#{to_zone_id}'
          AND vehicle_type = '#{vehicle_type}'
          AND time_band IS NULL
        LIMIT 1
      SQL

      if existing_base.empty?
        # Create base record by setting time_band = nil on the morning_rush record
        execute(<<~SQL)
          UPDATE zone_pair_vehicle_pricings
          SET time_band = NULL, updated_at = NOW()
          WHERE id = '#{base_record['id']}'
        SQL
        base_created += 1
        base_id = base_record['id']
      else
        base_id = existing_base.first['id']
        # Copy pricing from morning_rush to existing base
        execute(<<~SQL)
          UPDATE zone_pair_vehicle_pricings
          SET base_fare_paise = #{base_record['base_fare_paise']},
              per_km_rate_paise = #{base_record['per_km_rate_paise']},
              min_fare_paise = #{base_record['min_fare_paise']},
              per_min_rate_paise = #{base_record['per_min_rate_paise'].to_i},
              updated_at = NOW()
          WHERE id = '#{base_id}'
        SQL
        # Deactivate the morning_rush flat record since base already exists
        execute(<<~SQL)
          UPDATE zone_pair_vehicle_pricings
          SET active = false, updated_at = NOW()
          WHERE id = '#{base_record['id']}'
        SQL
        flat_deactivated += 1
      end

      # For each other band: create override if pricing differs from base
      other_records = records.reject { |r| r['id'] == base_record['id'] }
      other_records.each do |record|
        differs = record['base_fare_paise'] != base_record['base_fare_paise'] ||
                  record['per_km_rate_paise'] != base_record['per_km_rate_paise'] ||
                  record['min_fare_paise'] != base_record['min_fare_paise'] ||
                  record['per_min_rate_paise'].to_i != base_record['per_min_rate_paise'].to_i

        if differs
          # Create ZonePairVehicleTimePricing override
          execute(<<~SQL)
            INSERT INTO zone_pair_vehicle_time_pricings
              (id, zone_pair_vehicle_pricing_id, time_band, base_fare_paise, per_km_rate_paise,
               min_fare_paise, per_min_rate_paise, active, created_at, updated_at)
            VALUES
              (gen_random_uuid(), '#{base_id}', '#{record['time_band']}',
               #{record['base_fare_paise']}, #{record['per_km_rate_paise']},
               #{record['min_fare_paise']}, #{record['per_min_rate_paise'].to_i},
               true, NOW(), NOW())
          SQL
          overrides_created += 1
        end

        # Deactivate flat record (not delete, for rollback safety)
        execute(<<~SQL)
          UPDATE zone_pair_vehicle_pricings
          SET active = false, updated_at = NOW()
          WHERE id = '#{record['id']}'
        SQL
        flat_deactivated += 1
      end
    end

    say "Corridor two-tier migration: #{base_created} bases created, #{overrides_created} overrides created, #{flat_deactivated} flat records deactivated"
  end

  def down
    # Re-activate all deactivated flat records
    execute(<<~SQL)
      UPDATE zone_pair_vehicle_pricings
      SET active = true, updated_at = NOW()
      WHERE active = false AND time_band IS NOT NULL
    SQL

    # Remove all time pricing overrides
    execute("DELETE FROM zone_pair_vehicle_time_pricings")

    # Re-set morning_rush time_band on records that were converted to bases
    # (Records that had time_band set to NULL during migration)
    # Note: This is best-effort — manual verification recommended after rollback
    say "Rollback: re-activated flat records and removed overrides. Verify morning_rush bases manually."
  end
end
