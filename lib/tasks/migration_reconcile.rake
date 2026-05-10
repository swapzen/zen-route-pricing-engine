# frozen_string_literal: true

namespace :db do
  desc "Mark legacy pricing migrations as applied when schema objects already exist"
  task reconcile_legacy_migrations: :environment do
    conn = ActiveRecord::Base.connection

    checks = {
      "20250115130001" => -> { conn.table_exists?(:zone_distance_slabs) },
      "20260114081833" => -> { conn.column_exists?(:pricing_configs, :vendor_vehicle_code) },
      "20260114105910" => -> { conn.table_exists?(:pricing_distance_slabs) },
      "20260114110930" => -> { conn.table_exists?(:pricing_zone_multipliers) },
      "20260115082918" => -> { conn.table_exists?(:zone_vehicle_pricings) && conn.table_exists?(:zone_pair_vehicle_pricings) },
      "20260115133138" => -> { conn.table_exists?(:zone_vehicle_time_pricings) }
    }

    applied = 0

    migration_applied = lambda do |version|
      sql = "SELECT 1 FROM schema_migrations WHERE version = #{conn.quote(version)} LIMIT 1"
      conn.select_value(sql).present?
    end

    checks.each do |version, predicate|
      next if migration_applied.call(version)
      next unless predicate.call

      conn.execute("INSERT INTO schema_migrations (version) VALUES (#{conn.quote(version)})")
      puts "Marked migration #{version} as applied (schema already present)"
      applied += 1
    end

    puts(applied.zero? ? "No legacy migrations needed reconciliation" : "Reconciled #{applied} legacy migration(s)")
  end
end
