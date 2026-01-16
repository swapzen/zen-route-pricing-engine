#!/usr/bin/env ruby
# Cleanup script to remove temporary calibration, tuning, and debug files

files_to_remove = [
  # Root level temporary files
  'calibrate_by_zone.rb',
  'calibrate_granular.rb',
  'calibrate_pricing.rb',
  'test_pricing.rb',
  'test_all_vehicles.rb',
  'test_google_maps.rb',
  'test_time_multiplier_patterns.rb',
  'test_unit_economics.rb',
  
  # Script directory - Tuning iterations
  'script/tune_porter_round1.rb',
  'script/tune_porter_round2.rb',
  'script/tune_porter_round3.rb',
  'script/tune_porter_round4.rb',
  'script/tune_porter_round5.rb',
  'script/tune_porter_round6.rb',
  'script/tune_porter_round7.rb',
  'script/tune_porter_round8.rb',
  'script/tune_porter_round9.rb',
  'script/tune_porter_research_based.rb',
  'script/tune_porter_research_round2.rb',
  'script/tune_porter_research_round3.rb',
  'script/tune_porter_research_round4.rb',
  'script/tune_porter_final.rb',
  'script/tune_comprehensive.rb',
  'script/tune_fin_district_to_porter.rb',
  'script/tune_post_zone_fix.rb',
  'script/tune_industry_patterns.rb',
  
  # Script directory - Debug scripts
  'script/debug_route3.rb',
  'script/debug_route3_full.rb',
  'script/debug_route8_quote.rb',
  'script/debug_route9.rb',
  'script/debug_route9_full.rb',
  'script/debug_test_routes.rb',
  'script/debug_zone_bounds.rb',
  'script/debug_zone_mapping.rb',
  'script/debug_zones.rb',
  
  # Script directory - One-time fixes
  'script/fix_zone_boundaries.rb',
  'script/fix_zone_boundaries_v2.rb',
  
  # Script directory - Calibration scripts
  'script/calibrate_all_pricing.rb',
  'script/calibrate_from_actual_distances.rb',
  'script/calibrate_with_actual_distances.rb',
]

puts "=" * 80
puts "CLEANUP: Removing #{files_to_remove.length} unnecessary files"
puts "=" * 80

removed_count = 0
not_found_count = 0

files_to_remove.each do |file|
  file_path = File.join(__dir__, '..', file)
  if File.exist?(file_path)
    File.delete(file_path)
    puts "✅ Removed: #{file}"
    removed_count += 1
  else
    puts "⚠️  Not found: #{file}"
    not_found_count += 1
  end
end

puts "\n" + "=" * 80
puts "SUMMARY:"
puts "  ✅ Removed: #{removed_count} files"
puts "  ⚠️  Not found: #{not_found_count} files"
puts "=" * 80
