# frozen_string_literal: true

# =============================================================================
# Zone Management Rake Tasks
# =============================================================================
# Tasks for syncing zone configurations from YAML to database.
#
# USAGE:
#   rails zones:sync city=hyd              # Sync zones, pricing & corridors
#   rails zones:sync city=hyd force=true   # Force overwrite existing pricing
#   rails zones:sync city=hyd dry=true     # Dry run (no changes)
#   rails zones:list city=hyd              # List all zones for city
#   rails zones:pricing city=hyd           # Show pricing stats
#   rails zones:corridors city=hyd         # Show corridor stats
#   rails zones:status                     # Show all cities status
# =============================================================================

namespace :zones do
  desc "Sync zone configuration from YAML to database (zones + pricing + corridors)"
  task sync: :environment do
    city = ENV['city'] || 'hyd'
    dry_run = ENV['dry'] == 'true'
    force = ENV['force'] == 'true'
    
    puts "=" * 80
    puts "🗺️  ZONE SYNC: #{city.upcase}"
    puts "   Mode: #{force ? 'FORCE (overwrite)' : 'NORMAL (preserve edits)'}"
    puts "=" * 80
    
    loader = ZoneConfigLoader.new(city)
    
    if dry_run
      puts "\n📋 DRY RUN MODE (no changes will be made)\n"
      result = loader.dry_run
      
      if result[:success] == false
        puts "❌ Error: #{result[:error]}"
        exit 1
      end
      
      puts "City: #{result[:city_code]}"
      puts "Total zones in YAML: #{result[:total_zones_in_yaml]}"
      puts "Existing zones in DB: #{result[:existing_zones_in_db]}"
      puts "\n🆕 New zones to create (#{result[:new_zones].count}):"
      result[:new_zones].first(10).each { |z| puts "   - #{z}" }
      puts "   ... and #{result[:new_zones].count - 10} more" if result[:new_zones].count > 10
      puts "\n🔄 Zones to update (#{result[:zones_to_update].count}):"
      result[:zones_to_update].first(10).each { |z| puts "   - #{z}" }
      puts "   ... and #{result[:zones_to_update].count - 10} more" if result[:zones_to_update].count > 10
      puts "\n⚠️  In DB but not in YAML (#{result[:in_db_not_in_yaml].count}):"
      result[:in_db_not_in_yaml].each { |z| puts "   - #{z}" }
      puts "\n📁 Pricing files: #{result[:pricing_files].count}"
      result[:pricing_files].each { |f| puts "   - #{f}" }
      puts "\n📁 Corridor files: #{result[:corridor_files].count}"
      result[:corridor_files].each { |f| puts "   - #{f}" }
      puts "\n🧪 Validation:"
      puts "   Errors: #{result.dig(:validation, :errors)&.count || 0}"
      puts "   Warnings: #{result.dig(:validation, :warnings)&.count || 0}"

      if result.dig(:validation, :errors)&.any?
        puts "\n❌ Validation errors:"
        result[:validation][:errors].each { |e| puts "   - #{e}" }
      end

      if result.dig(:validation, :warnings)&.any?
        puts "\n⚠️  Validation warnings:"
        result[:validation][:warnings].each { |w| puts "   - #{w}" }
      end
    else
      puts "\n🔄 Syncing zones, pricing & corridors...\n"
      result = loader.sync!(force_pricing: force)
      
      if result[:success]
        s = result[:stats]
        puts "\n✅ Sync completed successfully!"
        puts "\n📍 ZONES:"
        puts "   Created: #{s[:zones_created]}"
        puts "   Updated: #{s[:zones_updated]}"
        puts "   Skipped: #{s[:zones_skipped]}"
        puts "\n💰 ZONE PRICING:"
        puts "   Zone pricings created: #{s[:zone_pricings_created]}"
        puts "   Zone pricings updated: #{s[:zone_pricings_updated]}"
        puts "   Time pricings created: #{s[:time_pricings_created]}"
        puts "\n🛤️  CORRIDORS:"
        puts "   Created: #{s[:corridors_created]}"
        puts "   Updated: #{s[:corridors_updated]}"
        puts "   Deactivated (stale): #{s[:corridors_deactivated]}"
        puts "   Conflicts skipped: #{s[:corridor_conflicts]}"
        puts "\n🧪 VALIDATION:"
        puts "   Errors: #{s[:validation_errors]&.count || 0}"
        puts "   Warnings: #{s[:validation_warnings]&.count || 0}"
        puts "\n❗ ERRORS: #{s[:errors].count}"

        if s[:validation_warnings]&.any?
          puts "\n⚠️  Validation warnings:"
          s[:validation_warnings].each { |w| puts "   - #{w}" }
        end
        
        if s[:errors].any?
          puts "\n⚠️  Errors:"
          s[:errors].each { |e| puts "   - #{e[:zone_code] || e[:file]}: #{e[:error]}" }
        end
      else
        puts "❌ Sync failed: #{result[:error]}"
        if result[:validation]
          errs = result.dig(:validation, :errors) || []
          warns = result.dig(:validation, :warnings) || []
          puts "Validation errors: #{errs.count}"
          errs.each { |e| puts "   - #{e}" }
          puts "Validation warnings: #{warns.count}"
          warns.each { |w| puts "   - #{w}" }
        end
        puts result[:backtrace].join("\n") if result[:backtrace]
        exit 1
      end
    end
    
    puts "\n" + "=" * 80
  end

  desc "List all zones for a city"
  task list: :environment do
    city = ENV['city'] || 'hyd'
    active_only = ENV['active'] == 'true'
    
    puts "=" * 80
    puts "🗺️  ZONES FOR: #{city.upcase}"
    puts "=" * 80
    
    zones = Zone.for_city(city).order(:zone_type, :zone_code)
    zones = zones.active if active_only
    
    puts "\n%-25s | %-22s | %-8s | %s" % ['Zone Code', 'Zone Type', 'Active', 'Name']
    puts "-" * 80
    
    zones.each do |z|
      status = z.status ? '✅' : '⬜'
      puts "%-25s | %-22s | %-8s | %s" % [z.zone_code, z.zone_type, status, z.name]
    end
    
    puts "-" * 80
    puts "Total: #{zones.count} zones"
    puts "Active: #{zones.select(&:status).count}"
    puts "Inactive: #{zones.reject(&:status).count}"
    puts "=" * 80
  end

  desc "Show zone pricing stats"
  task pricing: :environment do
    city = ENV['city'] || 'hyd'
    
    puts "=" * 80
    puts "💰 ZONE PRICING STATS: #{city.upcase}"
    puts "=" * 80
    
    zones_with_pricing = ZoneVehiclePricing.where(city_code: city.to_s.downcase)
                                           .distinct.pluck(:zone_id).count
    total_zone_pricings = ZoneVehiclePricing.where(city_code: city.to_s.downcase).count
    total_time_pricings = ZoneVehicleTimePricing.joins(:zone_vehicle_pricing)
                                                 .where('LOWER(zone_vehicle_pricings.city_code) = LOWER(?)', city)
                                                 .count
    
    puts "\n📊 Summary:"
    puts "   Zones with pricing: #{zones_with_pricing}"
    puts "   Total zone vehicle pricings: #{total_zone_pricings}"
    puts "   Total time-band pricings: #{total_time_pricings}"
    
    puts "\n📍 Zones with pricing by type:"
    ZoneVehiclePricing.where(city_code: city.to_s.downcase)
                      .joins(:zone)
                      .group('zones.zone_type')
                      .count
                      .each do |type, count|
      puts "   #{type}: #{count} zone-vehicle combinations"
    end
    
    puts "\n🚗 Pricing by vehicle type:"
    ZoneVehiclePricing.where(city_code: city.to_s.downcase)
                      .group(:vehicle_type)
                      .count
                      .each do |vtype, count|
      puts "   #{vtype}: #{count} zones"
    end
    
    puts "\n" + "=" * 80
  end

  desc "Show corridor stats"
  task corridors: :environment do
    city = ENV['city'] || 'hyd'
    
    puts "=" * 80
    puts "🛤️  CORRIDOR STATS: #{city.upcase}"
    puts "=" * 80
    
    total_corridors = ZonePairVehiclePricing.where(city_code: city.to_s.downcase).count
    unique_pairs = ZonePairVehiclePricing.where(city_code: city.to_s.downcase)
                                          .distinct
                                          .pluck(:from_zone_id, :to_zone_id)
                                          .count
    
    puts "\n📊 Summary:"
    puts "   Total corridor pricings: #{total_corridors}"
    puts "   Unique zone pairs: #{unique_pairs}"
    
    puts "\n🚗 Corridors by vehicle type:"
    ZonePairVehiclePricing.where(city_code: city.to_s.downcase)
                          .group(:vehicle_type)
                          .count
                          .each do |vtype, count|
      puts "   #{vtype}: #{count}"
    end
    
    puts "\n⏰ Corridors by time band:"
    ZonePairVehiclePricing.where(city_code: city.to_s.downcase)
                          .group(:time_band)
                          .count
                          .each do |band, count|
      puts "   #{band || 'all-day'}: #{count}"
    end
    
    puts "\n🛤️  Corridor pairs:"
    pairs = ZonePairVehiclePricing.where(city_code: city.to_s.downcase)
                                   .joins("LEFT JOIN zones from_z ON from_z.id = zone_pair_vehicle_pricings.from_zone_id")
                                   .joins("LEFT JOIN zones to_z ON to_z.id = zone_pair_vehicle_pricings.to_zone_id")
                                   .select("from_z.zone_code as from_code, to_z.zone_code as to_code")
                                   .distinct
                                   .limit(30)
    
    pairs.each do |p|
      puts "   #{p.from_code} → #{p.to_code}"
    end
    puts "   ... (showing first 30)" if pairs.count >= 30
    
    puts "\n" + "=" * 80
  end

  desc "Show zone sync status for all cities"
  task status: :environment do
    puts "=" * 80
    puts "🗺️  ZONE SYNC STATUS"
    puts "=" * 80
    
    config_dir = Rails.root.join('config', 'zones')
    
    Dir.glob(config_dir.join('*.yml')).each do |file|
      city = File.basename(file, '.yml')
      config = YAML.load_file(file) rescue nil
      
      next unless config
      
      # Get city code
      city_code = ZoneConfigLoader::CITY_FILE_MAPPING.key(city) || city
      
      yaml_count = (config['zones'] || {}).count
      db_count = Zone.for_city(city_code).count
      active_count = Zone.for_city(city_code).active.count
      pricing_count = ZoneVehiclePricing.where(city_code: city_code.to_s.downcase).count
      corridor_count = ZonePairVehiclePricing.where(city_code: city_code.to_s.downcase).count
      
      puts "\n#{city.upcase} (#{city_code}):"
      puts "  YAML zones: #{yaml_count}"
      puts "  DB zones: #{db_count} (active: #{active_count})"
      puts "  Zone pricings: #{pricing_count}"
      puts "  Corridors: #{corridor_count}"
      puts "  In sync: #{yaml_count == db_count ? '✅' : '⚠️ Run: rails zones:sync city=#{city_code}'}"
    end
    
    puts "\n" + "=" * 80
  end
  
  desc "Verify zone boundaries and coverage"
  task verify: :environment do
    city = ENV['city'] || 'hyd'
    
    puts "=" * 80
    puts "🔍 ZONE VERIFICATION: #{city.upcase}"
    puts "=" * 80
    
    zones = Zone.for_city(city).active.order(:zone_code)
    
    puts "\n📍 Active Zones: #{zones.count}"
    puts "-" * 80
    
    zones.first(20).each do |z|
      lat_range = "#{z.lat_min&.round(4)} - #{z.lat_max&.round(4)}"
      lng_range = "#{z.lng_min&.round(4)} - #{z.lng_max&.round(4)}"
      puts "%-20s | %-18s | Lat: %-18s | Lng: %s" % [z.zone_code, z.zone_type, lat_range, lng_range]
    end
    puts "... (showing first 20)" if zones.count > 20
    
    # Check for overlaps
    puts "\n🔄 Checking for overlapping zones..."
    overlaps = []
    
    zones.each do |z1|
      zones.each do |z2|
        next if z1.id >= z2.id
        
        if zones_overlap?(z1, z2)
          overlaps << [z1.zone_code, z2.zone_code]
        end
      end
    end
    
    if overlaps.any?
      puts "⚠️  Overlapping zones found (#{overlaps.count}):"
      overlaps.first(10).each { |pair| puts "   - #{pair[0]} <-> #{pair[1]}" }
      puts "   ... and #{overlaps.count - 10} more" if overlaps.count > 10
    else
      puts "✅ No overlapping zones found"
    end
    
    puts "\n" + "=" * 80
  end
  
  desc "Test a specific route against pricing"
  task test_route: :environment do
    city = ENV['city'] || 'hyd'
    pickup_lat = ENV['plat']&.to_f
    pickup_lng = ENV['plng']&.to_f
    drop_lat = ENV['dlat']&.to_f
    drop_lng = ENV['dlng']&.to_f
    vehicle = ENV['vehicle'] || 'two_wheeler'
    time_band = ENV['time'] || 'morning'
    
    unless pickup_lat && pickup_lng && drop_lat && drop_lng
      puts "Usage: rails zones:test_route city=hyd plat=17.4 plng=78.4 dlat=17.5 dlng=78.5 vehicle=two_wheeler time=morning"
      exit 1
    end
    
    puts "=" * 80
    puts "🧪 ROUTE TEST: #{city.upcase}"
    puts "=" * 80
    puts "Pickup: #{pickup_lat}, #{pickup_lng}"
    puts "Drop: #{drop_lat}, #{drop_lng}"
    puts "Vehicle: #{vehicle}"
    puts "Time: #{time_band}"
    puts "-" * 80
    
    resolver = RoutePricing::Services::ZonePricingResolver.new
    result = resolver.resolve(
      city_code: city,
      vehicle_type: vehicle,
      pickup_lat: pickup_lat,
      pickup_lng: pickup_lng,
      drop_lat: drop_lat,
      drop_lng: drop_lng,
      time_band: time_band
    )
    
    puts "\n📊 RESULT:"
    puts "   Source: #{result.source}"
    puts "   Base fare: ₹#{(result.base_fare_paise / 100.0).round(2)}"
    puts "   Per km rate: ₹#{(result.per_km_rate_paise / 100.0).round(2)}/km"
    puts "   Min fare: ₹#{(result.min_fare_paise / 100.0).round(2)}"
    puts "   Pricing mode: #{result.pricing_mode}"
    puts "\n📍 Zone Info:"
    puts "   Pickup zone: #{result.zone_info[:pickup_zone]} (#{result.zone_info[:pickup_type]})"
    puts "   Drop zone: #{result.zone_info[:drop_zone]} (#{result.zone_info[:drop_type]})"
    
    if result.zone_info[:formula_weights]
      puts "   Formula weights: #{result.zone_info[:formula_weights]}"
      puts "   Adjustment: #{result.zone_info[:adjustment_factor]}"
    end
    
    puts "\n" + "=" * 80
  end
  
  private
  
  def zones_overlap?(z1, z2)
    # Check if bounding boxes overlap
    !(z1.lat_max < z2.lat_min || z2.lat_max < z1.lat_min ||
      z1.lng_max < z2.lng_min || z2.lng_max < z1.lng_min)
  end
end
