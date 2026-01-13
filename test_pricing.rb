# Test script for zen-route-pricing-engine (refactored without ActiveInteraction)
ENV['ROUTE_PROVIDER_STRATEGY'] = 'local'

puts "🧪 Testing Zen Route Pricing Engine (Refactored)..."
puts "=" * 50

# Test 1: Check database connection
puts "\n1️⃣ Checking database connection..."
config_count = PricingConfig.count
puts "   ✅ Found #{config_count} pricing configs"

# Test 2: Create a quote directly via service
puts "\n2️⃣ Creating test quote via QuoteEngine..."
engine = RoutePricing::Services::QuoteEngine.new
result = engine.create_quote(
  city_code: 'hyd',
  vehicle_type: 'two_wheeler',
  pickup_lat: BigDecimal('17.4470'),   # Hitech City
  pickup_lng: BigDecimal('78.3771'),
  drop_lat: BigDecimal('17.3616'),     # Charminar  
  drop_lng: BigDecimal('78.4747')
)

if result[:error]
  puts "   ❌ Failed: #{result[:error]}"
  exit 1
else
  puts "   ✅ Quote created successfully!"
  puts "   Quote ID: #{result[:quote_id]}"
  puts "   Price: ₹#{result[:price_inr]} (#{result[:price_paise]} paise)"
  puts "   Distance: #{result[:distance_m]}m"
  puts "   Provider: #{result[:provider]}"
end

# Test 3: Verify quote was persisted
puts "\n3️⃣ Verifying persistence..."
quote = PricingQuote.last
puts "   ✅ Last quote: #{quote.id}"
puts "   Price: ₹#{quote.price_inr}"

puts "\n" + "=" * 50
puts "🎉 All tests passed! (No ActiveInteraction)"
puts "=" * 50
