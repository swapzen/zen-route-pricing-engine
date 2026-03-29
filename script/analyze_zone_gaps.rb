#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyzes zone resolution gaps for calibration endpoints
# Suggests H3 cell reassignments to fix conflicts
#
# Usage: bundle exec ruby script/analyze_zone_gaps.rb

require_relative '../config/environment'

CITY = 'hyd'

# Calibration endpoints (20 points from 10 routes)
ENDPOINTS = [
  { name: 'Gowlidoddi (R1/R2 pickup)', lat: 17.4293, lng: 78.3370, expected: 'fin_district' },
  { name: 'Storable (R1 drop)', lat: 17.4394, lng: 78.3577, expected: 'fin_district' },
  { name: 'DispatchTrack (R2 drop)', lat: 17.4406, lng: 78.3499, expected: 'fin_district' },
  { name: 'LB Nagar (R3/R5 pickup)', lat: 17.3515, lng: 78.5530, expected: 'lb_nagar_east' },
  { name: 'TCS Synergy (R3 drop)', lat: 17.3817, lng: 78.4801, expected: 'tcs_synergy' },
  { name: 'Ameerpet Metro (R4 drop, R6 pickup)', lat: 17.4379, lng: 78.4482, expected: 'ameerpet_core' },
  { name: 'Shantiniketan (R5 drop)', lat: 17.3700, lng: 78.5180, expected: 'lb_nagar_east' },
  { name: 'Nexus Mall / JNTU (R6 drop, R7 pickup)', lat: 17.4900, lng: 78.3900, expected: 'jntu_kukatpally' },
  { name: 'Charminar (R7/R8 drop)', lat: 17.3616, lng: 78.4747, expected: 'old_city' },
  { name: 'Vanasthali Puram (R8 pickup)', lat: 17.4000, lng: 78.5000, expected: 'amberpet' },
  { name: 'AMB Cinemas (R9 pickup)', lat: 17.4480, lng: 78.3900, expected: 'hitech_madhapur' },
  { name: 'Ayyappa Society (R9 drop, R10 pickup)', lat: 17.4500, lng: 78.4000, expected: 'hitech_madhapur' },
  { name: 'Gowlidoddi (R10 drop)', lat: 17.4293, lng: 78.3370, expected: 'fin_district' }
]

resolver = RoutePricing::Services::H3ZoneResolver.new(CITY)

puts "\n#{'=' * 100}"
puts "Zone Gap Analysis — Calibration Endpoints"
puts "#{'=' * 100}\n\n"

fixes_needed = []

ENDPOINTS.each do |ep|
  h3_r7_int = H3.from_geo_coordinates([ep[:lat].to_f, ep[:lng].to_f], 7)
  h3_r7_hex = h3_r7_int.to_s(16)

  h3_zone = resolver.resolve(ep[:lat], ep[:lng])
  current = h3_zone&.zone_code || 'NIL'
  expected = ep[:expected]

  mappings = ZoneH3Mapping.where(h3_index_r7: h3_r7_hex, city_code: CITY).includes(:zone)
  mapped_zones = mappings.map { |m| "#{m.zone.zone_code}(p#{m.zone.priority})" }

  status = current == expected ? '✅' : '❌'

  puts "#{status} #{ep[:name]}"
  puts "   Coords: #{ep[:lat]}, #{ep[:lng]}"
  puts "   H3 R7: #{h3_r7_hex}"
  puts "   Current: #{current} | Expected: #{expected}"
  puts "   Mapped zones: #{mapped_zones.join(', ')}"

  if current != expected
    # Find the expected zone
    expected_zone = Zone.find_by(zone_code: expected, city: CITY)
    if expected_zone
      puts "   FIX: Remove #{h3_r7_hex} from all zones except #{expected}"
      fixes_needed << {
        h3_hex: h3_r7_hex,
        keep_zone: expected,
        remove_from: mapped_zones.reject { |z| z.start_with?(expected) }.map { |z| z.split('(').first }
      }
    else
      puts "   ⚠️  Expected zone '#{expected}' not found in DB!"
    end
  end
  puts ""
end

puts "\n#{'=' * 100}"
puts "Summary of Required Fixes"
puts "#{'=' * 100}\n\n"

if fixes_needed.empty?
  puts "No fixes needed — all endpoints resolve correctly!"
else
  # Deduplicate by h3_hex
  unique_fixes = fixes_needed.uniq { |f| f[:h3_hex] }
  puts "#{unique_fixes.size} H3 cells need reassignment:\n\n"

  unique_fixes.each do |fix|
    puts "  #{fix[:h3_hex]}:"
    puts "    Keep: #{fix[:keep_zone]}"
    puts "    Remove from: #{fix[:remove_from].join(', ')}"
    puts ""
  end

  puts "\nTo apply fixes to h3_zones.yml, remove these cells from the listed zones."
  puts "Then run: rails \"zones:h3_sync[hyd]\" to sync changes to DB."
end

puts "\n#{'=' * 100}\n"
