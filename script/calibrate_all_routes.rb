#!/usr/bin/env ruby
# Calibration script to test each route and calculate required rate adjustments

require_relative '../config/environment'

ENV['PRICING_MODE'] = 'calibration'

routes = {
  'Route 5' => {
    coords: {from: {lat: 17.3667, lng: 78.5167}, to: {lat: 17.3700, lng: 78.5180}},
    targets: {morning: {two_wheeler: 52, scooter: 77, mini_3w: 131, three_wheeler: 266, tata_ace: 308, pickup_8ft: 418}}
  },
  'Route 6' => {
    coords: {from: {lat: 17.4379, lng: 78.4482}, to: {lat: 17.4900, lng: 78.3900}},
    targets: {morning: {two_wheeler: 102, scooter: 138, mini_3w: 207, three_wheeler: 470, tata_ace: 512, pickup_8ft: 611}}
  },
  'Route 8' => {
    coords: {from: {lat: 17.4000, lng: 78.5000}, to: {lat: 17.3616, lng: 78.4747}},
    targets: {morning: {two_wheeler: 129, scooter: 167, mini_3w: 234, three_wheeler: 543, tata_ace: 603, pickup_8ft: 696}}
  },
  'Route 9' => {
    coords: {from: {lat: 17.4480, lng: 78.3900}, to: {lat: 17.4500, lng: 78.4000}},
    targets: {morning: {two_wheeler: 64, scooter: 91, mini_3w: 146, three_wheeler: 324, tata_ace: 361, pickup_8ft: 471}}
  }
}

engine = RoutePricing::Services::QuoteEngine.new

routes.each do |route_name, data|
  puts "\n#{route_name}:"
  puts "-" * 60
  data[:targets][:morning].each do |vehicle, target|
    result = engine.create_quote(
      city_code: 'hyd',
      vehicle_type: vehicle.to_s,
      pickup_lat: data[:coords][:from][:lat],
      pickup_lng: data[:coords][:from][:lng],
      drop_lat: data[:coords][:to][:lat],
      drop_lng: data[:coords][:to][:lng],
      quote_time: Time.parse('2026-01-15 09:00:00')
    )
    actual = result[:price_inr].to_f
    ratio = target.to_f / actual
    diff_pct = ((actual - target) / target * 100).round(1)
    puts "  #{vehicle.to_s.ljust(18)}: Actual ₹#{actual.round(1)}, Target ₹#{target}, Ratio: #{ratio.round(3)}, Diff: #{diff_pct}%"
  end
end
