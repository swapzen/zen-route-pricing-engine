# frozen_string_literal: true

# =============================================================================
# EXTENSIVE ROUTE SIMULATION SCRIPT
# =============================================================================
# Generates quotes for routes across all Hyderabad zones, all vehicle types,
# and all time bands. Stores results in the pricing_quotes DB table AND
# writes a summary CSV.
#
# USAGE:
#   RAILS_ENV=development bundle exec ruby script/simulate_routes.rb [chunk_id] [total_chunks]
#
# chunk_id:      Which chunk to simulate (1-based). Default: all
# total_chunks:  How many chunks to split into. Default: 1
#
# Examples:
#   bundle exec ruby script/simulate_routes.rb              # Run all
#   bundle exec ruby script/simulate_routes.rb 1 12         # Chunk 1 of 12
#   bundle exec ruby script/simulate_routes.rb 5 12         # Chunk 5 of 12
# =============================================================================

require_relative '../config/environment'

CITY_CODE = 'hyd'
VEHICLE_TYPES = %w[two_wheeler scooter mini_3w three_wheeler tata_ace pickup_8ft canter_14ft].freeze
TIME_SLOTS = {
  'morning'   => '09:00',
  'afternoon' => '15:00',
  'evening'   => '23:00'
}.freeze

# Load all zone centroids
zones = Zone.where(city: CITY_CODE).where.not(lat_min: nil, lng_min: nil).map do |z|
  {
    code: z.zone_code,
    lat: ((z.lat_min.to_f + z.lat_max.to_f) / 2).round(4),
    lng: ((z.lng_min.to_f + z.lng_max.to_f) / 2).round(4),
    zone_type: z.zone_type
  }
end

puts "Loaded #{zones.size} zones with valid bounds"

# Build route pairs — strategic sampling to cover all zones
# Every zone should appear at least as pickup and as drop
routes = []

# 1. Hub-and-spoke from 5 major hubs to every zone
hubs = %w[hitech_madhapur secunderabad_cbd ameerpet_core old_city shamshabad]
hub_zones = zones.select { |z| hubs.include?(z[:code]) }

zones.each do |zone|
  hub_zones.each do |hub|
    next if zone[:code] == hub[:code]
    # Skip auto_* zones as hubs (but include them as destinations)
    routes << { pickup: hub, drop: zone, type: 'hub_spoke' }
  end
end

# 2. Intra-cluster routes (adjacent zones by proximity)
zones.each_with_index do |z1, i|
  zones[(i + 1)..].each do |z2|
    dist = Math.sqrt((z1[:lat] - z2[:lat])**2 + (z1[:lng] - z2[:lng])**2) * 111 # rough km
    if dist < 8 # Adjacent zones within ~8km straight-line
      routes << { pickup: z1, drop: z2, type: 'adjacent' }
    end
  end
end

# 3. Cross-city diagonals (long routes connecting peripherals)
peripheral_zones = zones.select { |z| z[:code].match?(/patancheru|ghatkesar|medchal|dundigal|shamshabad|adibatla|kompally|keesara|boduppal|vanasthali/) }
core_zones = zones.select { |z| z[:code].match?(/ameerpet|banjara|hitech|kondapur|secunderabad|jubilee|khairatabad|mehdipatnam/) }
peripheral_zones.each do |pz|
  core_zones.each do |cz|
    routes << { pickup: pz, drop: cz, type: 'peripheral_to_core' }
  end
end

# 4. Industrial corridors
industrial = zones.select { |z| z[:zone_type] == 'industrial' || z[:code].match?(/jeedimetla|nacharam|patancheru|adibatla/) }
industrial.each_with_index do |iz1, i|
  industrial[(i + 1)..].each do |iz2|
    routes << { pickup: iz1, drop: iz2, type: 'industrial_corridor' }
  end
  # Industrial to IT corridor
  zones.select { |z| z[:zone_type] == 'tech_corridor' }.each do |tz|
    routes << { pickup: iz1, drop: tz, type: 'industrial_to_tech' }
  end
end

# 5. Airport routes from every major zone
airport_zone = zones.find { |z| z[:code] == 'shamshabad' }
if airport_zone
  zones.reject { |z| z[:code] == 'shamshabad' || z[:code].start_with?('auto_') }.each do |z|
    routes << { pickup: airport_zone, drop: z, type: 'airport_outbound' }
    routes << { pickup: z, drop: airport_zone, type: 'airport_inbound' }
  end
end

# 6. Old city routes to major destinations
old_city_zones = zones.select { |z| z[:code].match?(/old_city|charminar|falaknuma|chandrayangutta|yakutpura|bahadurpura|golconda/) }
dest_zones = zones.select { |z| z[:code].match?(/hitech|kondapur|miyapur|kompally|secunderabad|lb_nagar|uppal/) }
old_city_zones.each do |oz|
  dest_zones.each do |dz|
    routes << { pickup: oz, drop: dz, type: 'old_city_to_new' }
  end
end

# 7. Growth corridor routes
growth_zones = zones.select { |z| z[:zone_type] == 'residential_growth' && !z[:code].start_with?('auto_') }
growth_zones.each do |gz|
  core_zones.each do |cz|
    routes << { pickup: gz, drop: cz, type: 'growth_to_core' }
  end
end

# Deduplicate (by pickup+drop pair)
routes.uniq! { |r| [r[:pickup][:code], r[:drop][:code]] }

# Cap routes to 250 max for manageable runtime
if routes.size > 250
  priority_routes = routes.select { |r| %w[hub_spoke airport_outbound airport_inbound].include?(r[:type]) }
  other_routes = routes - priority_routes
  needed = [250 - priority_routes.size, 0].max
  if needed > 0
    routes = priority_routes + other_routes.sample(needed)
  else
    routes = priority_routes.sample(250)
  end
  routes.shuffle!
end

puts "Generated #{routes.size} unique routes"

# Chunking support
chunk_id = (ARGV[0] || '0').to_i
total_chunks = (ARGV[1] || '1').to_i

if total_chunks > 1 && chunk_id > 0
  chunk_size = (routes.size.to_f / total_chunks).ceil
  start_idx = (chunk_id - 1) * chunk_size
  routes = routes[start_idx, chunk_size] || []
  puts "Chunk #{chunk_id}/#{total_chunks}: routes #{start_idx + 1}..#{start_idx + routes.size}"
end

total_scenarios = routes.size * VEHICLE_TYPES.size * TIME_SLOTS.size
puts "Total scenarios to simulate: #{total_scenarios}"
puts "=" * 80

# Output CSV
csv_path = Rails.root.join('tmp', "simulation_results_#{chunk_id || 'all'}.csv")
csv_file = File.open(csv_path, 'w')
csv_file.puts "route_id,pickup_zone,drop_zone,route_type,vehicle_type,time_band,distance_m,duration_s,price_paise,price_inr,vendor_paise,margin_paise,margin_pct,pricing_tier,confidence,pickup_h3_r7,drop_h3_r7"

# Quote engine
engine = RoutePricing::Services::QuoteEngine.new

success = 0
errors = 0
route_idx = 0

routes.each do |route|
  route_idx += 1
  route_name = "#{route[:pickup][:code]} → #{route[:drop][:code]}"

  TIME_SLOTS.each do |band, time_str|
    date = Date.today
    quote_time = Time.zone.parse("#{date} #{time_str}")

    VEHICLE_TYPES.each do |vehicle|
      begin
        result = engine.create_quote(
          pickup_lat: route[:pickup][:lat],
          pickup_lng: route[:pickup][:lng],
          drop_lat: route[:drop][:lat],
          drop_lng: route[:drop][:lng],
          vehicle_type: vehicle,
          city_code: CITY_CODE,
          quote_time: quote_time
        )

        if result[:success]
          price_inr = (result[:price_paise].to_f / 100).round
          # Fetch vendor data from the saved quote if available
          quote = PricingQuote.find_by(id: result[:quote_id])
          vendor = quote&.vendor_predicted_paise.to_i
          margin = quote&.margin_paise.to_i
          margin_pct = quote&.margin_pct.to_f.round(1)

          csv_file.puts [
            "#{route[:pickup][:code]}_to_#{route[:drop][:code]}",
            route[:pickup][:code], route[:drop][:code], route[:type],
            vehicle, band,
            result[:distance_m], result[:duration_s],
            result[:price_paise], price_inr,
            vendor, margin, margin_pct,
            result[:confidence] || 'estimated',
            result[:confidence],
            quote&.pickup_h3_r7, quote&.drop_h3_r7
          ].join(',')

          success += 1
        else
          errors += 1
        end
      rescue => e
        errors += 1
        $stderr.puts "  ERROR #{route_name}/#{vehicle}/#{band}: #{e.message}"
      end
    end
  end

  # Progress
  if route_idx % 20 == 0
    pct = (route_idx.to_f / routes.size * 100).round(1)
    puts "[#{pct}%] #{route_idx}/#{routes.size} routes | #{success} quotes | #{errors} errors"
  end
end

csv_file.close

puts
puts "=" * 80
puts "SIMULATION COMPLETE"
puts "  Routes: #{routes.size}"
puts "  Scenarios: #{routes.size * VEHICLE_TYPES.size * TIME_SLOTS.size}"
puts "  Successful quotes: #{success}"
puts "  Errors: #{errors}"
puts "  CSV: #{csv_path}"
puts "=" * 80
