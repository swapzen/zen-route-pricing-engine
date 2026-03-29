# frozen_string_literal: true

# =============================================================================
# Zone Expansion Rake Task
# =============================================================================
# Expands Hyderabad zones from YAML config into the database.
# The YAML at config/zones/hyderabad.yml defines 71 zones but db/seeds.rb
# only creates 14. This task seeds ALL zones from the YAML.
#
# USAGE:
#   bundle exec rake zones:expand_hyderabad
#   bundle exec rake zones:expand_hyderabad          # then run populate_h3
#   bundle exec rake zones:populate_h3_all[hyd]      # H3 mappings for all zones
# =============================================================================

namespace :zones do
  desc "Expand Hyderabad zones from YAML - seed all zones (not just the 14 from seeds.rb)"
  task expand_hyderabad: :environment do
    require 'yaml'

    city_code = 'hyd'
    yaml_path = Rails.root.join('config', 'zones', 'hyderabad.yml')

    unless File.exist?(yaml_path)
      puts "ERROR: #{yaml_path} not found"
      exit 1
    end

    config = YAML.load_file(yaml_path)
    zones_data = config['zones'] || {}

    created = 0
    skipped = 0
    errors = 0

    # Zone type to priority mapping (same defaults as seeds.rb and Zone model)
    zone_type_priority = {
      'tech_corridor'          => 20,
      'business_cbd'           => 15,
      'premium_residential'    => 12,
      'traditional_commercial' => 10,
      'heritage_commercial'    => 8,
      'residential_dense'      => 5,
      'residential_mixed'      => 3,
      'residential_growth'     => 2,
      'industrial'             => 1,
      'airport_logistics'      => 1
    }.freeze

    puts "Loading #{zones_data.size} zones from #{yaml_path}..."
    puts

    zones_data.each do |zone_code, zone_data|
      # Zone model uses `city` column (not city_code) and `status` (not active)
      existing = Zone.find_by(zone_code: zone_code, city: city_code)

      if existing
        puts "  SKIP  #{zone_code} (already exists, id: #{existing.id})"
        skipped += 1
        next
      end

      bounds = zone_data['bounds'] || {}
      mults = zone_data['multipliers'] || {}
      zone_type = zone_data['zone_type'] || 'residential_mixed'
      priority = zone_data['priority'] || zone_type_priority[zone_type] || 0

      begin
        zone = Zone.create!(
          zone_code: zone_code,
          name: zone_data['name'] || zone_code.titleize,
          city: city_code,
          zone_type: zone_type,
          status: zone_data.fetch('active', true),
          priority: priority,
          lat_min: bounds['lat_min'],
          lat_max: bounds['lat_max'],
          lng_min: bounds['lng_min'],
          lng_max: bounds['lng_max'],
          small_vehicle_mult: mults['small_vehicle'] || mults['default'] || 1.0,
          mid_truck_mult: mults['mid_truck'] || mults['default'] || 1.0,
          heavy_truck_mult: mults['heavy_truck'] || mults['default'] || 1.0,
          multiplier: mults['default'] || 1.0
        )
        puts "  CREATE #{zone_code} (#{zone_type}, priority: #{priority})"
        created += 1
      rescue => e
        puts "  ERROR  #{zone_code}: #{e.message}"
        errors += 1
      end
    end

    puts
    puts "=== Zone Expansion Complete ==="
    puts "  Created: #{created}"
    puts "  Skipped: #{skipped}"
    puts "  Errors:  #{errors}"
    puts "  Total in DB: #{Zone.where(city: city_code).count}"
    puts

    # Remind to populate H3 mappings for new zones
    if created > 0
      puts "Populating H3 mappings for new zones..."
      puts "Run: bundle exec rake zones:populate_h3[hyd]"
    end
  end
end
