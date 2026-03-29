# frozen_string_literal: true

# =============================================================================
# SIMULATION ANALYSIS & RECALIBRATION SCRIPT
# =============================================================================
# Reads simulation CSV files and produces:
# 1. Zone-level pricing analysis (avg price, min/max, spread)
# 2. Vehicle-type analysis (pricing consistency)
# 3. Margin analysis (vendor cost vs customer price)
# 4. Outlier detection (routes needing recalibration)
# 5. Coverage report (zones hit, H3 hex coverage)
#
# USAGE:
#   RAILS_ENV=development bundle exec ruby script/analyze_simulation.rb
# =============================================================================

require_relative '../config/environment'
require 'csv'

# Merge all chunk CSVs
csv_dir = Rails.root.join('tmp')
all_rows = []
headers = nil

Dir.glob(csv_dir.join('simulation_results_*.csv')).sort.each do |csv_path|
  CSV.foreach(csv_path, headers: true) do |row|
    headers ||= row.headers
    all_rows << row
  end
end

if all_rows.empty?
  puts "No simulation data found. Run script/simulate_routes.rb first."
  exit 1
end

puts "=" * 80
puts "SIMULATION ANALYSIS"
puts "=" * 80
puts "Total rows: #{all_rows.size}"
puts "Unique routes: #{all_rows.map { |r| r['route_id'] }.uniq.size}"
puts "Unique pickup zones: #{all_rows.map { |r| r['pickup_zone'] }.uniq.size}"
puts "Unique drop zones: #{all_rows.map { |r| r['drop_zone'] }.uniq.size}"
puts

# 1. PRICE DISTRIBUTION BY VEHICLE TYPE
puts "-" * 80
puts "1. PRICE DISTRIBUTION BY VEHICLE TYPE (INR)"
puts "-" * 80

vehicle_types = all_rows.map { |r| r['vehicle_type'] }.uniq.sort
vehicle_types.each do |vt|
  rows = all_rows.select { |r| r['vehicle_type'] == vt }
  prices = rows.map { |r| r['price_inr'].to_i }.sort
  next if prices.empty?

  avg = (prices.sum.to_f / prices.size).round
  min = prices.first
  max = prices.last
  median = prices[prices.size / 2]
  p25 = prices[(prices.size * 0.25).to_i]
  p75 = prices[(prices.size * 0.75).to_i]

  printf "  %-18s | Count: %4d | Min: %5d | P25: %5d | Median: %5d | Avg: %5d | P75: %5d | Max: %5d\n",
         vt, prices.size, min, p25, median, avg, p75, max
end
puts

# 2. PRICE DISTRIBUTION BY DISTANCE BAND
puts "-" * 80
puts "2. PRICE BY DISTANCE BAND (Tata Ace, Morning)"
puts "-" * 80

ace_morning = all_rows.select { |r| r['vehicle_type'] == 'tata_ace' && r['time_band'] == 'morning' }
bands = { '0-5km' => [0, 5000], '5-10km' => [5000, 10000], '10-15km' => [10000, 15000],
          '15-20km' => [15000, 20000], '20-30km' => [20000, 30000], '30-50km' => [30000, 50000],
          '50km+' => [50000, 999_999] }

bands.each do |label, (low, high)|
  rows = ace_morning.select { |r| r['distance_m'].to_i >= low && r['distance_m'].to_i < high }
  next if rows.empty?

  prices = rows.map { |r| r['price_inr'].to_i }
  avg = (prices.sum.to_f / prices.size).round
  avg_km = (rows.map { |r| r['distance_m'].to_i }.sum.to_f / rows.size / 1000).round(1)
  per_km = (avg.to_f / avg_km).round if avg_km > 0

  printf "  %-10s | Count: %3d | Avg Dist: %5.1f km | Avg Price: ₹%5d | Per KM: ₹%3d\n",
         label, rows.size, avg_km, avg, per_km || 0
end
puts

# 3. MARGIN ANALYSIS
puts "-" * 80
puts "3. MARGIN ANALYSIS (Vendor Predicted vs Customer Price)"
puts "-" * 80

with_vendor = all_rows.select { |r| r['vendor_paise'].to_i > 0 }
if with_vendor.any?
  vehicle_types.each do |vt|
    rows = with_vendor.select { |r| r['vehicle_type'] == vt }
    next if rows.empty?

    margins = rows.map { |r| r['margin_pct'].to_f }
    avg_margin = (margins.sum / margins.size).round(1)
    negative_count = margins.count { |m| m < 0 }
    negative_pct = (negative_count.to_f / margins.size * 100).round(1)

    printf "  %-18s | Count: %4d | Avg Margin: %6.1f%% | Negative: %3d (%5.1f%%)\n",
           vt, rows.size, avg_margin, negative_count, negative_pct
  end
else
  puts "  No vendor data available in simulation results."
end
puts

# 4. ZONE COVERAGE
puts "-" * 80
puts "4. ZONE COVERAGE"
puts "-" * 80

all_zones = Zone.where(city: 'hyd').pluck(:zone_code)
pickup_zones = all_rows.map { |r| r['pickup_zone'] }.uniq
drop_zones = all_rows.map { |r| r['drop_zone'] }.uniq
all_covered = (pickup_zones + drop_zones).uniq
uncovered = all_zones - all_covered

puts "  Total zones in DB: #{all_zones.size}"
puts "  Zones as pickup: #{pickup_zones.size}"
puts "  Zones as drop: #{drop_zones.size}"
puts "  Total covered: #{all_covered.size}"
puts "  Uncovered: #{uncovered.size}"
if uncovered.any?
  puts "  Missing zones: #{uncovered.join(', ')}"
end
puts

# 5. H3 HEX COVERAGE
puts "-" * 80
puts "5. H3 HEX COVERAGE"
puts "-" * 80

pickup_hexes = all_rows.map { |r| r['pickup_h3_r7'] }.compact.uniq
drop_hexes = all_rows.map { |r| r['drop_h3_r7'] }.compact.uniq
all_hexes = (pickup_hexes + drop_hexes).uniq

puts "  Unique pickup H3 R7: #{pickup_hexes.size}"
puts "  Unique drop H3 R7: #{drop_hexes.size}"
puts "  Total unique H3 R7: #{all_hexes.size}"
puts

# 6. OUTLIER ROUTES (high per-km cost suggesting miscalibration)
puts "-" * 80
puts "6. OUTLIER ROUTES (Per-KM > ₹50 or < ₹5 for Tata Ace)"
puts "-" * 80

ace_routes = all_rows.select { |r| r['vehicle_type'] == 'tata_ace' && r['distance_m'].to_i > 2000 }
ace_routes.each do |r|
  dist_km = r['distance_m'].to_f / 1000
  per_km = (r['price_inr'].to_f / dist_km).round(1)
  if per_km > 50 || per_km < 5
    printf "  %-40s | %5.1f km | ₹%5d | ₹%5.1f/km | %s | %s\n",
           "#{r['pickup_zone']} → #{r['drop_zone']}", dist_km, r['price_inr'].to_i,
           per_km, r['time_band'], r['pricing_tier']
  end
end
puts

# 7. TIME BAND PREMIUM ANALYSIS
puts "-" * 80
puts "7. TIME BAND PREMIUM (Evening vs Morning, Tata Ace)"
puts "-" * 80

route_ids = all_rows.select { |r| r['vehicle_type'] == 'tata_ace' }.map { |r| r['route_id'] }.uniq
premiums = []
route_ids.each do |rid|
  morning = all_rows.find { |r| r['route_id'] == rid && r['vehicle_type'] == 'tata_ace' && r['time_band'] == 'morning' }
  evening = all_rows.find { |r| r['route_id'] == rid && r['vehicle_type'] == 'tata_ace' && r['time_band'] == 'evening' }
  if morning && evening && morning['price_inr'].to_i > 0
    premium = ((evening['price_inr'].to_f - morning['price_inr'].to_f) / morning['price_inr'].to_f * 100).round(1)
    premiums << premium
  end
end

if premiums.any?
  avg_premium = (premiums.sum / premiums.size).round(1)
  puts "  Routes analyzed: #{premiums.size}"
  puts "  Avg evening premium: #{avg_premium}%"
  puts "  Min: #{premiums.min}% | Max: #{premiums.max}%"
  puts "  Routes with >50% premium: #{premiums.count { |p| p > 50 }}"
end
puts

# Write combined CSV
combined_path = Rails.root.join('tmp', 'simulation_combined.csv')
CSV.open(combined_path, 'w') do |csv|
  csv << headers
  all_rows.each { |row| csv << row.fields }
end
puts "Combined CSV: #{combined_path}"
puts "=" * 80
