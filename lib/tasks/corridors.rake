# frozen_string_literal: true

namespace :corridors do
  desc "Analyze top zone pairs by volume and flag corridor candidates. Usage: rails corridors:analyze[hyd,30]"
  task :analyze, [:city_code, :days] => :environment do |_t, args|
    city_code = args[:city_code] || 'hyd'
    days = (args[:days] || 30).to_i

    puts "=== Corridor Analysis: #{city_code} (last #{days} days) ==="
    puts ""

    unless defined?(PricingOutcome) && PricingOutcome.table_exists?
      puts "ERROR: pricing_outcomes table not found. Run migrations first."
      next
    end

    # Query top zone pairs by volume
    since = days.days.ago
    zone_pairs = PricingOutcome
      .where(city_code: city_code)
      .where('created_at >= ?', since)
      .where.not(pickup_zone_code: nil)
      .where.not(drop_zone_code: nil)
      .group(:pickup_zone_code, :drop_zone_code)
      .select(
        :pickup_zone_code,
        :drop_zone_code,
        'COUNT(*) as trip_count',
        'AVG(CASE WHEN outcome = \'accepted\' THEN 1 ELSE 0 END) as acceptance_rate',
        'AVG(price_paise) as avg_price_paise'
      )
      .order('trip_count DESC')
      .limit(50)

    if zone_pairs.empty?
      puts "No pricing outcomes found for #{city_code} in the last #{days} days."
      puts "Tip: Ensure pricing_outcomes are being recorded (via PricingOutcome.record!)."
      next
    end

    # Load existing corridors for comparison
    existing_corridors = Set.new
    if defined?(ZonePairVehiclePricing)
      ZonePairVehiclePricing.where(city_code: city_code, active: true)
        .pluck(:from_zone_id, :to_zone_id)
        .each { |from_id, to_id| existing_corridors.add([from_id, to_id].sort) }
    end

    # Map zone codes to IDs
    zone_id_map = Zone.for_city(city_code).pluck(:zone_code, :id).to_h

    puts format("%-4s %-20s %-20s %8s %10s %12s %s",
                "#", "Pickup Zone", "Drop Zone", "Trips", "Accept %", "Avg Price", "Status")
    puts "-" * 95

    zone_pairs.each_with_index do |pair, idx|
      pickup_code = pair.pickup_zone_code
      drop_code = pair.drop_zone_code
      trip_count = pair.trip_count
      accept_rate = (pair.acceptance_rate.to_f * 100).round(1)
      avg_price = (pair.avg_price_paise.to_f / 100).round(0)

      pickup_id = zone_id_map[pickup_code]
      drop_id = zone_id_map[drop_code]
      pair_key = [pickup_id, drop_id].compact.sort

      status = if existing_corridors.include?(pair_key)
                 "[CORRIDOR EXISTS]"
               elsif trip_count >= 20 && accept_rate >= 50
                 "[CANDIDATE - HIGH]"
               elsif trip_count >= 10
                 "[CANDIDATE]"
               else
                 ""
               end

      puts format("%-4d %-20s %-20s %8d %9.1f%% %11s %s",
                  idx + 1, pickup_code, drop_code, trip_count, accept_rate, "Rs #{avg_price}", status)
    end

    puts ""
    puts "Legend:"
    puts "  [CORRIDOR EXISTS]   — Already has corridor pricing configured"
    puts "  [CANDIDATE - HIGH]  — 20+ trips, 50%+ acceptance → strong corridor candidate"
    puts "  [CANDIDATE]         — 10+ trips → review for corridor creation"
    puts ""
    puts "To create a corridor: add zone pair to config/zones/hyderabad/corridors/*.yml"
    puts "Then run: rails zones:h3_sync[#{city_code}]"
  end
end
