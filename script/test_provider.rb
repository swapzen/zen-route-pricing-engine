# frozen_string_literal: true
#
# Test GoogleMapsProvider directly
# Run: bundle exec rails runner script/test_provider.rb

puts "\n=== Testing GoogleMapsProvider ===\n"

provider = RoutePricing::Services::Providers::GoogleMapsProvider.new

result = provider.get_route(
  pickup_lat: 17.3515,
  pickup_lng: 78.5530,
  drop_lat: 17.3817,
  drop_lng: 78.4801
)

puts "Provider: #{result[:provider]}"
puts "Distance: #{result[:distance_m]}m (#{(result[:distance_m]/1000.0).round(2)}km)"
puts "Duration: #{result[:duration_s]}s"
puts "Duration in traffic: #{result[:duration_in_traffic_s]}s"

if result[:provider] == 'google'
  puts "\n✅ Google Maps API is working!"
else
  puts "\n⚠️ Using haversine fallback"
end
