#!/usr/bin/env ruby
# Quick command to check route pricing
# Usage: PRICING_MODE=calibration ROUTE_PROVIDER_STRATEGY=google bundle exec rails runner script/check_route_pricing.rb

require_relative '../config/environment'

ENV['PRICING_MODE'] ||= 'calibration'
ENV['ROUTE_PROVIDER_STRATEGY'] ||= 'google'

engine = RoutePricing::Services::QuoteEngine.new

# Test routes from the test script
test_routes = [
  {name: "Route 1", pickup: [17.3850, 78.4867], drop: [17.3900, 78.4900], time: "09:00", vehicles: ['two_wheeler', 'scooter']},
  {name: "Route 2", pickup: [17.3850, 78.4867], drop: [17.4000, 78.5000], time: "09:00", vehicles: ['two_wheeler']},
  {name: "Route 3", pickup: [17.4000, 78.5000], drop: [17.4500, 78.5500], time: "09:00", vehicles: ['two_wheeler']},
  {name: "Route 5", pickup: [17.3667, 78.5167], drop: [17.3700, 78.5180], time: "09:00", vehicles: ['two_wheeler']},
  {name: "Route 9", pickup: [17.4480, 78.3900], drop: [17.4500, 78.4000], time: "09:00", vehicles: ['two_wheeler']},
]

puts "=" * 80
puts "ROUTE PRICING CHECK"
puts "=" * 80

test_routes.each do |route|
  puts "\n#{route[:name]}:"
  route[:vehicles].each do |vehicle|
    quote_time = Time.parse("2026-01-15 #{route[:time]}:00")
    result = engine.create_quote(
      city_code: 'hyd',
      vehicle_type: vehicle,
      pickup_lat: route[:pickup][0],
      pickup_lng: route[:pickup][1],
      drop_lat: route[:drop][0],
      drop_lng: route[:drop][1],
      quote_time: quote_time
    )
    puts "  #{vehicle.ljust(18)}: ₹#{result[:price_inr].round(1)} (Distance: #{result[:distance_m] / 1000.0}km)"
  end
end

puts "\n" + "=" * 80
puts "Run full test: PRICING_MODE=calibration ROUTE_PROVIDER_STRATEGY=google bundle exec rails runner script/test_pricing_engine.rb"
puts "=" * 80
