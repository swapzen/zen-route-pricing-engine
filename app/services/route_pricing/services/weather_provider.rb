# frozen_string_literal: true

require 'net/http'
require 'json'

module RoutePricing
  module Services
    class WeatherProvider
      CACHE_TTL = 30.minutes

      # City center coordinates for weather lookups
      CITY_CENTERS = {
        'hyd' => { lat: 17.385, lng: 78.4867 },
        'blr' => { lat: 12.9716, lng: 77.5946 },
        'mum' => { lat: 19.0760, lng: 72.8777 },
        'del' => { lat: 28.6139, lng: 77.2090 },
        'chn' => { lat: 13.0827, lng: 80.2707 },
        'pun' => { lat: 18.5204, lng: 73.8567 }
      }.freeze

      # Map Google Weather API weatherCondition.type codes to our multiplier keys
      CONDITION_MAP = {
        'CLEAR' => 'clear',
        'MOSTLY_CLEAR' => 'clear',
        'PARTLY_CLOUDY' => 'clouds',
        'CLOUDY' => 'clouds',
        'MOSTLY_CLOUDY' => 'clouds',
        'OVERCAST' => 'clouds',
        'FOG' => 'fog',
        'LIGHT_FOG' => 'fog',
        'DRIZZLE' => 'drizzle',
        'LIGHT_RAIN' => 'rain_light',
        'RAIN' => 'rain_light',
        'HEAVY_RAIN' => 'rain_heavy',
        'SNOW' => 'storm',
        'THUNDERSTORM' => 'storm',
        'HAIL' => 'storm'
      }.freeze

      DEFAULT_WEATHER_MULTIPLIERS = {
        'clear' => 1.0,
        'clouds' => 1.0,
        'drizzle' => 1.05,
        'rain_light' => 1.10,
        'rain_heavy' => 1.20,
        'fog' => 1.08,
        'storm' => 1.25,
        'extreme_heat' => 1.05
      }.freeze

      def initialize
        @api_key = ENV['GOOGLE_MAPS_API_KEY']
      end

      # Returns: {condition: "rain_light", multiplier_key: "rain_light", temp_c: 28, humidity_pct: 85}
      def current_weather(city_code:)
        center = CITY_CENTERS[city_code.to_s.downcase]
        return default_weather unless center

        time_bucket = (Time.current.to_i / 1800) # 30-min bucket
        cache_key = "weather:#{city_code}:#{time_bucket}"

        cached = Rails.cache.read(cache_key)
        return cached if cached

        weather = fetch_weather(center[:lat], center[:lng])
        Rails.cache.write(cache_key, weather, expires_in: CACHE_TTL)
        weather
      rescue StandardError => e
        Rails.logger.warn("WeatherProvider error: #{e.message}")
        default_weather
      end

      private

      def fetch_weather(lat, lng)
        return default_weather unless @api_key.present?

        uri = URI('https://weather.googleapis.com/v1/currentConditions:lookup')
        uri.query = URI.encode_www_form(
          'key' => @api_key,
          'location.latitude' => lat,
          'location.longitude' => lng
        )

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 5

        if Rails.env.development? || Rails.env.test?
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        request = Net::HTTP::Get.new(uri)
        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("Weather API returned #{response.code}")
          return default_weather
        end

        parse_weather_response(JSON.parse(response.body))
      rescue StandardError => e
        Rails.logger.warn("Weather fetch failed: #{e.message}")
        default_weather
      end

      def parse_weather_response(data)
        # Google Weather API response: top-level fields (no wrapper)
        # weatherCondition.type, temperature.degrees, relativeHumidity
        condition_code = data.dig('weatherCondition', 'type') || 'CLEAR'
        temp_c = data.dig('temperature', 'degrees')
        humidity = data['relativeHumidity']

        multiplier_key = CONDITION_MAP[condition_code] || 'clear'

        # Check for extreme heat (> 42°C common in Indian summers)
        if temp_c && temp_c > 42 && multiplier_key == 'clear'
          multiplier_key = 'extreme_heat'
        end

        {
          condition: multiplier_key,
          multiplier_key: multiplier_key,
          temp_c: temp_c,
          humidity_pct: humidity
        }
      rescue StandardError
        default_weather
      end

      def default_weather
        { condition: 'clear', multiplier_key: 'clear', temp_c: nil, humidity_pct: nil }
      end
    end
  end
end
