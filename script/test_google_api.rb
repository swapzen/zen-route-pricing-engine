# frozen_string_literal: true
#
# Test Google Maps API connectivity
# Run: bundle exec rails runner script/test_google_api.rb

require 'net/http'
require 'json'
require 'uri'

puts "\n=== Google Maps API Test ===\n"

api_key = ENV['GOOGLE_MAPS_API_KEY']
puts "API Key present: #{api_key.present?}"
puts "API Key (first 10 chars): #{api_key&.first(10)}..."
puts "Route Strategy: #{ENV['ROUTE_PROVIDER_STRATEGY']}"

# Test Route 3 coordinates
origin = "17.3515,78.5530"
destination = "17.3817,78.4801"

url = URI("https://maps.googleapis.com/maps/api/distancematrix/json")
params = {
  origins: origin,
  destinations: destination,
  key: api_key,
  departure_time: 'now',
  traffic_model: 'best_guess'
}
url.query = URI.encode_www_form(params)

puts "\nCalling Google Maps Distance Matrix API..."
puts "URL: #{url.to_s.gsub(api_key, 'API_KEY_HIDDEN')}"

begin
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10
  
  request = Net::HTTP::Get.new(url)
  response = http.request(request)
  
  puts "\nResponse Status: #{response.code}"
  data = JSON.parse(response.body)
  puts "Response Status from API: #{data['status']}"
  
  if data['status'] == 'OK'
    element = data['rows'][0]['elements'][0]
    if element['status'] == 'OK'
      distance_m = element['distance']['value']
      duration_s = element['duration']['value']
      duration_traffic_s = element['duration_in_traffic']&.dig('value')
      
      puts "\n✅ API Working!"
      puts "   Distance: #{distance_m}m (#{(distance_m/1000.0).round(2)}km)"
      puts "   Duration: #{duration_s}s"
      puts "   Duration in traffic: #{duration_traffic_s}s"
    else
      puts "\n❌ Element status: #{element['status']}"
    end
  else
    puts "\n❌ API Error: #{data['status']}"
    puts "   Error message: #{data['error_message']}" if data['error_message']
  end
rescue => e
  puts "\n❌ HTTP Error: #{e.class} - #{e.message}"
end

puts "\n=== Test Complete ==="
