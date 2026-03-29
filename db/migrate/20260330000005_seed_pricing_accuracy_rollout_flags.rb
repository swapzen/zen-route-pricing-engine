# frozen_string_literal: true

class SeedPricingAccuracyRolloutFlags < ActiveRecord::Migration[8.0]
  def up
    # All new pricing accuracy features start DISABLED
    # Enable one-by-one after calibration testing
    flags = %w[route_segment_pricing weather_pricing backhaul_pricing cancellation_risk_pricing]

    flags.each do |flag_name|
      # Check if flag already exists (NULL-safe for city_code)
      exists = execute("SELECT 1 FROM pricing_rollout_flags WHERE flag_name = '#{flag_name}' AND city_code IS NULL LIMIT 1").any?
      next if exists

      execute <<-SQL
        INSERT INTO pricing_rollout_flags (id, flag_name, city_code, enabled, rollout_pct, metadata, created_at, updated_at)
        VALUES (gen_random_uuid(), '#{flag_name}', NULL, false, 100, '{}', NOW(), NOW())
      SQL
    end
  end

  def down
    execute <<-SQL
      DELETE FROM pricing_rollout_flags
      WHERE flag_name IN ('route_segment_pricing', 'weather_pricing', 'backhaul_pricing', 'cancellation_risk_pricing')
      AND city_code IS NULL
    SQL
  end
end
