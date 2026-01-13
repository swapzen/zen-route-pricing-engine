# Test script with Google Maps API
puts "🗺️  Testing with Google Maps Distance Matrix API..."
puts "=" * 60

# Check API key
unless ENV['GOOGLE_MAPS_API_KEY']
  puts "❌ ERROR: GOOGLE_MAPS_API_KEY not set!"
  puts "\nTo fix, run:"
  puts "  export GOOGLE_MAPS_API_KEY='your_key_here'"
  exit 1
end

# Set to use Google Maps
ENV['ROUTE_PROVIDER_STRATEGY'] = 'google'

puts "✅ API Key: #{ENV['GOOGLE_MAPS_API_KEY'][0..10]}..." 
puts "✅ Provider: google\n"
puts "=" * 60

# Test route: Hitech City to Charminar (Hyderabad)
puts "\n📍 Test Route:"
puts "   Pickup: Hitech City (17.4470, 78.3771)"
puts "   Drop: Charminar (17.3616, 78.4747)"
puts "   Vehicle: two_wheeler\n"

# Create quote
engine = RoutePricing::Services::QuoteEngine.new
result = engine.create_quote(
  city_code: 'hyd',
  vehicle_type: 'two_wheeler',
  pickup_lat: BigDecimal('17.4470'),
  pickup_lng: BigDecimal('78.3771'),
  drop_lat: BigDecimal('17.3616'),
  drop_lng: BigDecimal('78.4747')
)

if result[:error]
  puts "❌ Failed: #{result[:error]}"
  exit 1
end

puts "=" * 60
puts "✅ QUOTE CREATED SUCCESSFULLY"
puts "=" * 60

puts "\n💰 Pricing:"
puts "   Quote ID: #{result[:quote_id]}"
puts "   Final Price: ₹#{result[:price_inr]}"
puts "   Price (paise): #{result[:price_paise]}"

puts "\n📏 Route Info:"
puts "   Distance: #{result[:distance_m]}m (~#{(result[:distance_m] / 1000.0).round(1)}km)"
puts "   Duration: #{result[:duration_s]}s (~#{(result[:duration_s] / 60.0).round(1)} min)"
if result[:duration_in_traffic_s]
  puts "   Duration in Traffic: #{result[:duration_in_traffic_s]}s (~#{(result[:duration_in_traffic_s] / 60.0).round(1)} min)"
  traffic_ratio = (result[:duration_in_traffic_s].to_f / result[:duration_s]).round(2)
  puts "   Traffic Ratio: #{traffic_ratio}x"
end

puts "\n🔧 Meta:"
puts "   Provider: #{result[:provider]}"
puts "   Confidence: #{result[:confidence]}"
puts "   Version: #{result[:pricing_version]}"

puts "\n📊 Breakdown:"
breakdown = result[:breakdown]
puts "   Base Fare: ₹#{breakdown[:base_fare] / 100.0}"
puts "   Distance Component: ₹#{breakdown[:distance_component] / 100.0}"
puts "   Surge Multiplier: #{breakdown[:surge_multiplier_applied]}x"
puts "   After Multipliers: ₹#{breakdown[:after_multipliers] / 100.0}"
puts "   Variance Buffer: ₹#{breakdown[:variance_buffer] / 100.0}"
puts "   Margin Guardrail: ₹#{breakdown[:margin_guardrail] / 100.0}"

puts "\n" + "=" * 60
puts "🎉 Google Maps API Test Complete!"
puts "=" * 60

# Compare with Haversine
puts "\n🔬 Comparing with Haversine fallback..."
ENV['ROUTE_PROVIDER_STRATEGY'] = 'local'
haversine_result = engine.create_quote(
  city_code: 'hyd',
  vehicle_type: 'two_wheeler',
  pickup_lat: BigDecimal('17.4470'),
  pickup_lng: BigDecimal('78.3771'),
  drop_lat: BigDecimal('17.3616'),
  drop_lng: BigDecimal('78.4747')
)

if haversine_result[:error].nil?
  puts "   Google Maps Price: ₹#{result[:price_inr]}"
  puts "   Haversine Price: ₹#{haversine_result[:price_inr]}"
  puts "   Difference: ₹#{(result[:price_inr] - haversine_result[:price_inr]).abs}"
  puts "   Google Distance: #{result[:distance_m]}m"
  puts "   Haversine Distance: #{haversine_result[:distance_m]}m"
end
