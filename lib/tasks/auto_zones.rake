# frozen_string_literal: true

# =============================================================================
# Auto-Zone Generation Rake Tasks
# =============================================================================
# Generate, preview, and manage auto-zones from H3 grid.
#
# USAGE:
#   rails zones:auto_preview[hyd]    — dry-run, shows what would be created
#   rails zones:auto_generate[hyd]   — create auto-zones
#   rails zones:auto_stats[hyd]      — show current auto-zone stats
#   rails zones:auto_remove[hyd]     — remove all auto-generated zones
# =============================================================================

namespace :zones do
  desc "Preview auto-zone generation (dry run)"
  task :auto_preview, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    unless defined?(H3)
      puts "H3 gem not available. Run: bundle install"
      exit 1
    end

    puts "Previewing auto-zone generation for #{city_code}..."
    result = RoutePricing::AutoZones::Orchestrator.new(city_code, dry_run: true).run!

    if result[:success]
      puts "\n=== Auto-Zone Preview ==="
      puts "Total unassigned cells: #{result[:total_cells]}"
      puts "Classified cells:       #{result[:classified]}"
      puts "Clusters to create:     #{result[:zones_to_create]}"

      puts "\nType breakdown:"
      (result[:type_breakdown] || {}).sort_by { |_, v| -v }.each do |type, count|
        puts "  #{type}: #{count} cells"
      end

      puts "\nConfidence breakdown:"
      (result[:confidence_breakdown] || {}).each do |level, count|
        puts "  #{level}: #{count} cells"
      end

      puts "\nCluster summary:"
      (result[:cluster_summary] || []).each do |c|
        puts "  #{c[:zone_code]} (#{c[:zone_type]}, #{c[:cells]} cells, parent: #{c[:parent] || 'none'})"
      end
    else
      puts "Preview failed: #{result[:error] || result[:message]}"
    end
  end

  desc "Generate auto-zones from H3 grid"
  task :auto_generate, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    unless defined?(H3)
      puts "H3 gem not available. Run: bundle install"
      exit 1
    end

    puts "Generating auto-zones for #{city_code}..."
    result = RoutePricing::AutoZones::Orchestrator.new(city_code).run!

    if result[:success]
      stats = result[:stats] || {}
      puts "\n=== Auto-Zone Generation Complete ==="
      puts "Generation version: #{result[:generation_version]}"
      puts "Zones created:      #{stats[:zones_created]}"
      puts "Cells mapped:       #{stats[:cells_mapped]}"
      puts "Pricing records:    #{stats[:pricing_records]}"
      puts "\n#{result[:message]}" if result[:message]
    else
      puts "Generation failed: #{result[:error] || result[:message]}"
      exit 1
    end
  end

  desc "Show auto-zone stats for a city"
  task :auto_stats, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    auto_zones = Zone.for_city(city_code).where(auto_generated: true)
    manual_zones = Zone.for_city(city_code).where(auto_generated: false).active

    puts "=== Auto-Zone Stats for #{city_code} ==="
    puts "Manual zones (active): #{manual_zones.count}"
    puts "Auto-generated zones:  #{auto_zones.count}"
    puts "  Active:              #{auto_zones.active.count}"
    puts "  Total cells:         #{auto_zones.sum(:cell_count)}"

    versions = auto_zones.distinct.pluck(:generation_version).compact.sort
    puts "  Generation versions: #{versions.join(', ')}" if versions.any?

    puts "\nBy zone_type:"
    auto_zones.group(:zone_type).count.sort_by { |_, v| -v }.each do |type, count|
      cells = auto_zones.where(zone_type: type).sum(:cell_count)
      puts "  #{type}: #{count} zones, #{cells} cells"
    end

    total_h3 = ZoneH3Mapping.for_city(city_code).count
    auto_h3 = ZoneH3Mapping.for_city(city_code)
                            .joins(:zone)
                            .where(zones: { auto_generated: true })
                            .count
    puts "\nH3 mappings: #{total_h3} total, #{auto_h3} from auto-zones"
  end

  desc "Remove all auto-generated zones for a city"
  task :auto_remove, [:city_code] => :environment do |_t, args|
    city_code = args[:city_code] || ENV['city'] || 'hyd'

    auto_zones = Zone.for_city(city_code).where(auto_generated: true)
    count = auto_zones.count

    if count.zero?
      puts "No auto-generated zones found for #{city_code}"
      exit 0
    end

    puts "Removing #{count} auto-generated zones for #{city_code}..."
    auto_zones.destroy_all
    puts "Done! Removed #{count} auto-zones and their associated records."
  end
end
