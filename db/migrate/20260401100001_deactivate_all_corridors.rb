# frozen_string_literal: true

class DeactivateAllCorridors < ActiveRecord::Migration[8.0]
  def up
    # Deactivate all corridor base records
    execute <<~SQL
      UPDATE zone_pair_vehicle_pricings
      SET active = false, updated_at = NOW()
      WHERE active = true
    SQL

    # Deactivate all corridor time-band overrides
    execute <<~SQL
      UPDATE zone_pair_vehicle_time_pricings
      SET active = false, updated_at = NOW()
      WHERE active = true
    SQL
  end

  def down
    # No automatic rollback — corridors can be re-enabled via admin or h3_sync
    Rails.logger.warn("DeactivateAllCorridors: rollback is a no-op. Re-enable corridors manually if needed.")
  end
end
