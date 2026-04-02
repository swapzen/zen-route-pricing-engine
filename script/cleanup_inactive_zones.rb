#!/usr/bin/env ruby
# Cleans up all inactive (stale) zones and their FK dependencies
require_relative '../config/environment'

inactive_zone_ids = Zone.where(city: 'hyd', status: false).pluck(:id)
puts "Inactive zones to clean: #{inactive_zone_ids.size}"
exit(0) if inactive_zone_ids.empty?

id_list = inactive_zone_ids.map { |id| "'#{id}'" }.join(',')
conn = ActiveRecord::Base.connection

# Tables with zone_id FK
zone_id_tables = %w[
  backhaul_probabilities
  zone_distance_slabs
  zone_h3_mappings
  zone_locations
  zone_vehicle_pricings
]

# Must delete zone_vehicle_time_pricings before zone_vehicle_pricings
zvp_ids = conn.select_values("SELECT id FROM zone_vehicle_pricings WHERE zone_id IN (#{id_list})")
if zvp_ids.any?
  zvp_list = zvp_ids.map { |id| "'#{id}'" }.join(',')
  count = conn.execute("DELETE FROM zone_vehicle_time_pricings WHERE zone_vehicle_pricing_id IN (#{zvp_list})").cmd_tuples
  puts "  zone_vehicle_time_pricings: #{count} deleted"
end

# Delete from zone_id tables
zone_id_tables.each do |table|
  count = conn.execute("DELETE FROM #{table} WHERE zone_id IN (#{id_list})").cmd_tuples
  puts "  #{table}: #{count} deleted" if count > 0
end

# Tables with pickup_zone_id / drop_zone_id
%w[pricing_benchmark_routes].each do |table|
  %w[pickup_zone_id drop_zone_id].each do |col|
    # Nullify instead of delete (preserve benchmark data)
    count = conn.execute("UPDATE #{table} SET #{col} = NULL WHERE #{col} IN (#{id_list})").cmd_tuples
    puts "  #{table}.#{col}: #{count} nullified" if count > 0
  end
end

# Tables with from_zone_id / to_zone_id
%w[zone_pair_vehicle_pricings].each do |table|
  # Delete zone_pair_vehicle_time_pricings first
  zpvp_ids = conn.select_values("SELECT id FROM #{table} WHERE from_zone_id IN (#{id_list}) OR to_zone_id IN (#{id_list})")
  if zpvp_ids.any?
    zpvp_list = zpvp_ids.map { |id| "'#{id}'" }.join(',')
    count = conn.execute("DELETE FROM zone_pair_vehicle_time_pricings WHERE zone_pair_vehicle_pricing_id IN (#{zpvp_list})").cmd_tuples
    puts "  zone_pair_vehicle_time_pricings: #{count} deleted" if count > 0
  end
  count = conn.execute("DELETE FROM #{table} WHERE from_zone_id IN (#{id_list}) OR to_zone_id IN (#{id_list})").cmd_tuples
  puts "  #{table}: #{count} deleted" if count > 0
end

# Nullify zone_id on shared tables (admins, users — don't delete those!)
%w[admins users].each do |table|
  begin
    count = conn.execute("UPDATE #{table} SET zone_id = NULL WHERE zone_id IN (#{id_list})").cmd_tuples
    puts "  #{table}.zone_id: #{count} nullified" if count > 0
  rescue => e
    puts "  #{table}: skip (#{e.message[0..60]})"
  end
end

# Nullify/delete remaining FK tables
%w[listing_approval_settings referral_rules zone_delivery_configs zone_listing_rules zone_policies].each do |table|
  begin
    count = conn.execute("DELETE FROM #{table} WHERE zone_id IN (#{id_list})").cmd_tuples
    puts "  #{table}: #{count} deleted" if count > 0
  rescue => e
    puts "  #{table}: skip (#{e.message[0..60]})"
  end
end

# Now delete the zones
count = Zone.where(id: inactive_zone_ids).delete_all
puts "\nDeleted #{count} inactive zones"

# Final state
puts "\n=== FINAL STATE ==="
puts "Active zones: #{Zone.where(city: 'hyd', status: true).count}"
puts "Inactive zones: #{Zone.where(city: 'hyd', status: false).count}"
puts "ZoneVehiclePricing: #{ZoneVehiclePricing.joins(:zone).where(zones: { city: 'hyd' }).count}"
puts "ZoneVehicleTimePricing: #{ZoneVehicleTimePricing.joins(zone_vehicle_pricing: :zone).where(zones: { city: 'hyd' }).count}"
puts "ZoneH3Mapping: #{ZoneH3Mapping.where(city_code: 'hyd').count}"
