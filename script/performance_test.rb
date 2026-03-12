# frozen_string_literal: true

# Performance & Critical Bug Testing Script
# Run: RAILS_ENV=development bundle exec ruby script/performance_test.rb

require_relative '../config/environment'
require 'benchmark'

puts "=" * 90
puts "PRICING ENGINE - PERFORMANCE & CRITICAL BUG TEST SUITE"
puts "=" * 90

CITY = 'hyd'
VEHICLE = 'two_wheeler'

# HITEC City to Gachibowli (known route)
PICKUP = { lat: 17.4435, lng: 78.3772 }
DROP   = { lat: 17.4401, lng: 78.3489 }

errors_found = []
warnings_found = []

# ============================================================================
# TEST 1: Single quote latency
# ============================================================================
puts "\n[TEST 1] Single quote latency (5 runs, warm cache)"

engine = RoutePricing::Services::QuoteEngine.new

# Warm up (first call hits Google Maps)
warm = engine.create_quote(
  city_code: CITY, vehicle_type: VEHICLE,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: DROP[:lat], drop_lng: DROP[:lng]
)

if warm[:error]
  puts "  SKIP - Quote engine error: #{warm[:error]}"
  errors_found << "TEST 1: Quote engine returned error: #{warm[:error]}"
else
  times = []
  5.times do |i|
    t = Benchmark.realtime do
      engine.create_quote(
        city_code: CITY, vehicle_type: VEHICLE,
        pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
        drop_lat: DROP[:lat], drop_lng: DROP[:lng]
      )
    end
    times << (t * 1000).round(1)
  end

  avg = (times.sum / times.size).round(1)
  min = times.min
  max = times.max
  puts "  Latencies: #{times.map { |t| "#{t}ms" }.join(', ')}"
  puts "  Avg: #{avg}ms | Min: #{min}ms | Max: #{max}ms"

  if avg > 500
    errors_found << "TEST 1: Single quote avg latency #{avg}ms exceeds 500ms threshold"
  elsif avg > 200
    warnings_found << "TEST 1: Single quote avg latency #{avg}ms is slow (>200ms)"
  else
    puts "  PASS (< 200ms)"
  end
end

# ============================================================================
# TEST 2: Multi-quote latency + N+1 analysis
# ============================================================================
puts "\n[TEST 2] Multi-quote latency (all vehicle types)"

multi_times = []
3.times do
  t = Benchmark.realtime do
    engine.create_multi_quote(
      city_code: CITY,
      pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
      drop_lat: DROP[:lat], drop_lng: DROP[:lng]
    )
  end
  multi_times << (t * 1000).round(1)
end

multi_avg = (multi_times.sum / multi_times.size).round(1)
puts "  Latencies: #{multi_times.map { |t| "#{t}ms" }.join(', ')}"
puts "  Avg: #{multi_avg}ms"

single_avg = times ? (times.sum / times.size) : 100.0
vehicle_count = ZoneConfigLoader::VEHICLE_TYPES.size
theoretical_parallel = single_avg.round(1)
ratio = (multi_avg / single_avg).round(1) rescue 'N/A'

puts "  Vehicle types: #{vehicle_count}"
puts "  Ratio vs single: #{ratio}x (ideal: ~1x since route cached)"

if multi_avg > 3000
  errors_found << "TEST 2: Multi-quote #{multi_avg}ms exceeds 3s threshold"
elsif multi_avg > 1500
  warnings_found << "TEST 2: Multi-quote #{multi_avg}ms is slow (>1.5s)"
else
  puts "  PASS"
end

# ============================================================================
# TEST 3: Round-trip quote latency
# ============================================================================
puts "\n[TEST 3] Round-trip quote latency"

rt_times = []
3.times do
  t = Benchmark.realtime do
    engine.create_round_trip_quote(
      city_code: CITY, vehicle_type: VEHICLE,
      pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
      drop_lat: DROP[:lat], drop_lng: DROP[:lng]
    )
  end
  rt_times << (t * 1000).round(1)
end

rt_avg = (rt_times.sum / rt_times.size).round(1)
puts "  Latencies: #{rt_times.map { |t| "#{t}ms" }.join(', ')}"
puts "  Avg: #{rt_avg}ms (expected ~2x single quote)"

if rt_avg > 2000
  errors_found << "TEST 3: Round-trip #{rt_avg}ms exceeds 2s threshold"
else
  puts "  PASS"
end

# ============================================================================
# TEST 4: Edge case - zero/negative distance
# ============================================================================
puts "\n[TEST 4] Edge cases - zero distance (same pickup/drop)"

same_point = engine.create_quote(
  city_code: CITY, vehicle_type: VEHICLE,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: PICKUP[:lat], drop_lng: PICKUP[:lng]
)

if same_point[:error]
  puts "  Zero distance returned error: #{same_point[:error]}"
  if same_point[:price_paise].nil?
    puts "  INFO: Error returned (acceptable for zero-distance)"
  end
else
  price = same_point[:price_paise]
  puts "  Zero distance price: #{price} paise (Rs #{price / 100.0})"
  if price <= 0
    errors_found << "TEST 4: Zero distance returned price #{price} <= 0"
  else
    puts "  PASS (returns min fare)"
  end
end

# ============================================================================
# TEST 5: Weight multiplier edge cases
# ============================================================================
puts "\n[TEST 5] Weight multiplier edge cases"

calc = RoutePricing::Services::PriceCalculator.new(
  config: PricingConfig.current_version(CITY, VEHICLE)
)

test_weights = [nil, 0, -5, 10, 15, 50, 200, 500, 99999]
test_weights.each do |w|
  mult = calc.send(:calculate_weight_multiplier, w)
  label = w.nil? ? 'nil' : "#{w}kg"
  status = mult >= 1.0 ? 'OK' : 'BAD'
  status = 'BAD' if mult == 0.0
  puts "  weight=#{label.ljust(8)} -> multiplier=#{mult} [#{status}]"
  if mult <= 0.0
    errors_found << "TEST 5: Weight #{w}kg returned multiplier #{mult} (should be >= 1.0)"
  end
end

# ============================================================================
# TEST 6: Scheduled discount edge cases
# ============================================================================
puts "\n[TEST 6] Scheduled discount edge cases"

config = PricingConfig.current_version(CITY, VEHICLE)
calc2 = RoutePricing::Services::PriceCalculator.new(config: config)

test_times = {
  "now" => Time.current,
  "+30min" => Time.current + 30.minutes,
  "+3h (should discount)" => Time.current + 3.hours,
  "+24h" => Time.current + 24.hours,
  "-1h (past)" => Time.current - 1.hour
}

test_times.each do |label, qt|
  info = calc2.send(:calculate_scheduled_discount, 10000, qt)
  applied = info[:applied] ? "DISCOUNT #{info[:discount_pct]}%" : "no discount"
  puts "  #{label.ljust(25)} -> #{applied} (#{info[:discounted_price_paise]} paise)"
end

# ============================================================================
# TEST 7: Quote validity - expiry check
# ============================================================================
puts "\n[TEST 7] Quote validity lifecycle"

fresh_quote = engine.create_quote(
  city_code: CITY, vehicle_type: VEHICLE,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: DROP[:lat], drop_lng: DROP[:lng]
)

unless fresh_quote[:error]
  q = PricingQuote.find(fresh_quote[:quote_id])
  puts "  Quote created: #{q.id}"
  puts "  valid_until: #{q.valid_until}"
  puts "  expired?: #{q.expired?}"
  puts "  remaining_seconds: #{q.remaining_seconds}"

  if q.valid_until.nil?
    errors_found << "TEST 7: Quote created without valid_until"
  elsif q.expired?
    errors_found << "TEST 7: Freshly created quote is already expired"
  elsif q.remaining_seconds <= 0
    errors_found << "TEST 7: Freshly created quote has 0 remaining seconds"
  else
    puts "  PASS"
  end
end

# ============================================================================
# TEST 8: Round-trip linking integrity
# ============================================================================
puts "\n[TEST 8] Round-trip quote linking integrity"

rt_result = engine.create_round_trip_quote(
  city_code: CITY, vehicle_type: VEHICLE,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: DROP[:lat], drop_lng: DROP[:lng]
)

unless rt_result[:error]
  outbound_q = PricingQuote.find(rt_result[:outbound][:quote_id])
  return_q = PricingQuote.find(rt_result[:return][:quote_id])

  puts "  Outbound: #{outbound_q.id} | trip_leg=#{outbound_q.trip_leg} | linked=#{outbound_q.linked_quote_id}"
  puts "  Return:   #{return_q.id} | trip_leg=#{return_q.trip_leg} | linked=#{return_q.linked_quote_id}"

  issues = []
  issues << "outbound trip_leg not 'outbound'" unless outbound_q.trip_leg == 'outbound'
  issues << "return trip_leg not 'return'" unless return_q.trip_leg == 'return'
  issues << "outbound not linked to return" unless outbound_q.linked_quote_id == return_q.id
  issues << "return not linked to outbound" unless return_q.linked_quote_id == outbound_q.id

  discount = rt_result[:round_trip_summary]
  puts "  Combined: Rs #{discount[:combined_price_inr]} | Discount: #{discount[:return_discount_pct]}% (Rs #{discount[:savings_inr]})"
  puts "  Discounted total: Rs #{discount[:discounted_total_inr]}"

  issues << "no discount applied" if discount[:discount_paise] <= 0
  issues << "discounted > original" if discount[:discounted_total_paise] >= discount[:combined_price_paise]

  if issues.any?
    issues.each { |i| errors_found << "TEST 8: #{i}" }
    puts "  FAIL: #{issues.join(', ')}"
  else
    puts "  PASS"
  end
end

# ============================================================================
# TEST 9: Surge transparency - every quote has surge_reasons
# ============================================================================
puts "\n[TEST 9] Surge transparency in breakdown"

q_result = engine.create_quote(
  city_code: CITY, vehicle_type: VEHICLE,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: DROP[:lat], drop_lng: DROP[:lng]
)

unless q_result[:error]
  bd = q_result[:breakdown]
  sr = bd[:surge_reasons]

  if sr.nil?
    errors_found << "TEST 9: surge_reasons missing from breakdown"
    puts "  FAIL: surge_reasons is nil"
  elsif !sr.is_a?(Array)
    errors_found << "TEST 9: surge_reasons is not an array"
    puts "  FAIL: surge_reasons type = #{sr.class}"
  else
    puts "  surge_reasons: #{sr}"
    sr.each do |reason|
      unless reason[:code] && reason[:label] && reason[:multiplier]
        errors_found << "TEST 9: surge_reason missing fields: #{reason}"
      end
    end
    puts "  PASS (#{sr.size} reason(s))"
  end

  # Also check weight_kg and weight_multiplier keys exist
  unless bd.key?(:weight_kg) && bd.key?(:weight_multiplier)
    errors_found << "TEST 9: weight fields missing from breakdown"
  end
end

# ============================================================================
# TEST 10: Database query count for single quote
# ============================================================================
puts "\n[TEST 10] Database query count for single quote"

query_count = 0
counter = lambda { |*_args|
  query_count += 1
}

ActiveSupport::Notifications.subscribe('sql.active_record', &counter)

query_count = 0
engine.create_quote(
  city_code: CITY, vehicle_type: VEHICLE,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: DROP[:lat], drop_lng: DROP[:lng]
)

ActiveSupport::Notifications.unsubscribe(counter)

puts "  Total SQL queries: #{query_count}"
if query_count > 20
  errors_found << "TEST 10: #{query_count} SQL queries (possible N+1, should be <20)"
elsif query_count > 10
  warnings_found << "TEST 10: #{query_count} SQL queries (consider optimization)"
else
  puts "  PASS (<= 10 queries)"
end

# ============================================================================
# TEST 11: Database query count for multi-quote
# ============================================================================
puts "\n[TEST 11] Database query count for multi-quote"

query_count = 0
counter2 = lambda { |*_args|
  query_count += 1
}

ActiveSupport::Notifications.subscribe('sql.active_record', &counter2)

query_count = 0
engine.create_multi_quote(
  city_code: CITY,
  pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
  drop_lat: DROP[:lat], drop_lng: DROP[:lng]
)

ActiveSupport::Notifications.unsubscribe(counter2)

vehicle_count = ZoneConfigLoader::VEHICLE_TYPES.size
puts "  Total SQL queries: #{query_count} (for #{vehicle_count} vehicles)"
puts "  Queries per vehicle: #{(query_count.to_f / vehicle_count).round(1)}"

if query_count > 100
  errors_found << "TEST 11: #{query_count} queries for multi-quote (severe N+1)"
elsif query_count > 50
  warnings_found << "TEST 11: #{query_count} queries for multi-quote (N+1 likely)"
else
  puts "  PASS"
end

# ============================================================================
# TEST 12: Memory usage for multi-quote burst
# ============================================================================
puts "\n[TEST 12] Memory usage for 10x multi-quote burst"

GC.start
before_mem = `ps -o rss= -p #{Process.pid}`.strip.to_i

10.times do
  engine.create_multi_quote(
    city_code: CITY,
    pickup_lat: PICKUP[:lat], pickup_lng: PICKUP[:lng],
    drop_lat: DROP[:lat], drop_lng: DROP[:lng]
  )
end

GC.start
after_mem = `ps -o rss= -p #{Process.pid}`.strip.to_i
delta_kb = after_mem - before_mem
delta_mb = (delta_kb / 1024.0).round(1)

puts "  Memory before: #{before_mem} KB"
puts "  Memory after:  #{after_mem} KB"
puts "  Delta: #{delta_mb} MB"

if delta_mb > 50
  errors_found << "TEST 12: Memory grew #{delta_mb}MB during burst (possible leak)"
elsif delta_mb > 20
  warnings_found << "TEST 12: Memory grew #{delta_mb}MB during burst"
else
  puts "  PASS (<20MB growth)"
end

# ============================================================================
# TEST 13: Inter-zone config cache growth
# ============================================================================
puts "\n[TEST 13] Inter-zone config cache size"

cache = RoutePricing::Services::ZonePricingResolver.inter_zone_config_cache
timestamps = RoutePricing::Services::ZonePricingResolver.inter_zone_cache_timestamps
puts "  Cache entries: #{cache.size}"
puts "  Cache keys: #{cache.keys}"
puts "  TTL: #{RoutePricing::Services::ZonePricingResolver::INTER_ZONE_CACHE_TTL / 60} minutes"
puts "  Timestamps: #{timestamps.transform_values { |t| t.strftime('%H:%M:%S') }}"

if cache.size > 20
  warnings_found << "TEST 13: Inter-zone cache has #{cache.size} entries (may need TTL)"
elsif timestamps.empty? && cache.any?
  errors_found << "TEST 13: Cache has entries but no TTL timestamps"
else
  puts "  PASS (TTL-enabled cache)"
end

# ============================================================================
# TEST 14: Concurrent quote creation safety
# ============================================================================
puts "\n[TEST 14] Concurrent quote creation (5 threads)"

threads = []
results = []
mutex = Mutex.new

5.times do |i|
  threads << Thread.new do
    e = RoutePricing::Services::QuoteEngine.new
    r = e.create_quote(
      city_code: CITY, vehicle_type: VEHICLE,
      pickup_lat: PICKUP[:lat] + (i * 0.001),
      pickup_lng: PICKUP[:lng],
      drop_lat: DROP[:lat],
      drop_lng: DROP[:lng]
    )
    mutex.synchronize { results << r }
  end
end

threads.each(&:join)

successes = results.count { |r| r[:success] }
failures = results.count { |r| r[:error] }
puts "  Successes: #{successes}/5 | Failures: #{failures}/5"

if failures > 0
  warnings_found << "TEST 14: #{failures}/5 concurrent requests failed"
else
  puts "  PASS"
end

# ============================================================================
# SUMMARY
# ============================================================================
puts "\n" + "=" * 90
puts "TEST SUMMARY"
puts "=" * 90

if errors_found.empty? && warnings_found.empty?
  puts "\nALL TESTS PASSED"
else
  if errors_found.any?
    puts "\nERRORS (#{errors_found.size}):"
    errors_found.each { |e| puts "  #{e}" }
  end

  if warnings_found.any?
    puts "\nWARNINGS (#{warnings_found.size}):"
    warnings_found.each { |w| puts "  #{w}" }
  end
end

total = 14
passed = total - errors_found.size
puts "\nResult: #{passed}/#{total} passed | #{errors_found.size} errors | #{warnings_found.size} warnings"
puts "=" * 90
