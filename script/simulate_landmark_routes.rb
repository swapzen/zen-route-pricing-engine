#!/usr/bin/env ruby
# frozen_string_literal: true

# Landmark-based route simulation across Hyderabad
# Generates ~70-80 routes x 7 vehicles x 8 time bands = ~4,000-4,500 scenarios
#
# Usage:
#   PRICING_MODE=calibration RAILS_ENV=development bundle exec ruby script/simulate_landmark_routes.rb
#
# Output: tmp/simulation_landmarks.csv

require_relative '../config/environment'
require 'csv'

VEHICLES = %w[two_wheeler scooter mini_3w three_wheeler tata_ace pickup_8ft canter_14ft].freeze

BAND_TIMES = {
  'early_morning' => { time: '06:30', day: :wednesday },
  'morning_rush'  => { time: '09:30', day: :wednesday },
  'midday'        => { time: '12:30', day: :wednesday },
  'afternoon'     => { time: '15:30', day: :wednesday },
  'evening_rush'  => { time: '18:30', day: :wednesday },
  'night'         => { time: '23:00', day: :wednesday },
  'weekend_day'   => { time: '14:00', day: :saturday },
  'weekend_night' => { time: '22:00', day: :saturday },
}.freeze

def load_landmarks
  path = Rails.root.join('config', 'landmarks', 'hyderabad.yml')
  yaml = YAML.load_file(path)

  all = []
  yaml['landmarks'].each do |category, items|
    items.each do |item|
      all << item.merge('category' => category)
    end
  end
  all
end

def classify_distance(distance_m)
  km = distance_m / 1000.0
  case km
  when 0...3    then 'micro'
  when 3...8    then 'short'
  when 8...18   then 'medium'
  when 18...35  then 'long'
  else               'very_long'
  end
end

def build_quote_time(band_key)
  config = BAND_TIMES[band_key]
  target_day_sym = config[:day]

  wday_map = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 }
  target_wday = wday_map[target_day_sym]

  date = Date.today
  days_ahead = (target_wday - date.wday) % 7
  days_ahead = 7 if days_ahead == 0 && date.wday != target_wday
  date += days_ahead if date.wday != target_wday

  Time.zone.parse("#{date} #{config[:time]}")
end

def generate_routes(landmarks)
  routes = []
  used_pairs = Set.new

  categories = landmarks.group_by { |l| l['category'] }

  # Cross-category routes (highest priority)
  cross_pairs = [
    %w[hospitals malls],
    %w[hospitals tech_parks],
    %w[tech_parks malls],
    %w[tech_parks transport],
    %w[residential tech_parks],
    %w[residential malls],
    %w[residential hospitals],
    %w[residential transport],
    %w[transport landmarks],
    %w[landmarks malls],
    %w[transport hospitals],
    %w[schools residential],
  ]

  cross_pairs.each do |from_cat, to_cat|
    from_list = categories[from_cat] || []
    to_list = categories[to_cat] || []

    from_list.each do |from|
      to_list.each do |to|
        next if from['id'] == to['id']
        pair_key = [from['id'], to['id']].sort.join(':')
        next if used_pairs.include?(pair_key)

        used_pairs.add(pair_key)
        routes << { pickup: from, drop: to }
        break if routes.size >= 80
      end
      break if routes.size >= 80
    end
    break if routes.size >= 80
  end

  # Fill remaining with intra-category if needed
  if routes.size < 60
    categories.each do |_cat, items|
      items.combination(2).each do |from, to|
        pair_key = [from['id'], to['id']].sort.join(':')
        next if used_pairs.include?(pair_key)

        used_pairs.add(pair_key)
        routes << { pickup: from, drop: to }
        break if routes.size >= 80
      end
      break if routes.size >= 80
    end
  end

  routes
end

# ============================================================================
# MAIN
# ============================================================================

puts "Loading landmarks..."
landmarks = load_landmarks
puts "  Loaded #{landmarks.size} landmarks"

puts "Generating routes..."
routes = generate_routes(landmarks)
puts "  Generated #{routes.size} routes"

engine = RoutePricing::Services::QuoteEngine.new
output_path = Rails.root.join('tmp', 'simulation_landmarks.csv')
total_scenarios = routes.size * VEHICLES.size * BAND_TIMES.size
completed = 0
errors = 0

CSV.open(output_path, 'w') do |csv|
  csv << %w[
    route_id pickup_landmark drop_landmark pickup_address drop_address
    pickup_lat pickup_lng drop_lat drop_lng pickup_zone drop_zone
    distance_m distance_category vehicle_type time_band
    price_paise price_inr pricing_source
  ]

  routes.each_with_index do |route, route_idx|
    pickup = route[:pickup]
    drop = route[:drop]
    route_id = "#{pickup['id']}→#{drop['id']}"

    BAND_TIMES.each_key do |band|
      quote_time = build_quote_time(band)

      VEHICLES.each do |vt|
        begin
          result = engine.create_quote(
            city_code: 'hyd',
            vehicle_type: vt,
            pickup_lat: pickup['lat'],
            pickup_lng: pickup['lng'],
            drop_lat: drop['lat'],
            drop_lng: drop['lng'],
            quote_time: quote_time
          )

          if result[:success]
            distance_m = result[:distance_m]
            breakdown = result[:breakdown] || {}
            zone_info = breakdown[:zone_info] || {}

            csv << [
              route_id,
              pickup['id'],
              drop['id'],
              pickup['name'],
              drop['name'],
              pickup['lat'],
              pickup['lng'],
              drop['lat'],
              drop['lng'],
              zone_info[:pickup_zone],
              zone_info[:drop_zone],
              distance_m,
              classify_distance(distance_m.to_i),
              vt,
              band,
              result[:price_paise],
              (result[:price_paise].to_f / 100).round,
              breakdown[:pricing_source]
            ]
          else
            errors += 1
          end
        rescue StandardError => e
          errors += 1
          $stderr.puts "  ERROR: #{route_id} / #{band} / #{vt}: #{e.message}"
        end

        completed += 1
        print "\r  Progress: #{completed}/#{total_scenarios} (#{errors} errors)" if completed % 50 == 0
      end
    end
  end
end

puts "\n\nDone!"
puts "  Total scenarios: #{completed}"
puts "  Errors: #{errors}"
puts "  Output: #{output_path}"
