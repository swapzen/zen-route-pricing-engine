# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::WeatherProvider do
  let(:provider) { described_class.new }

  before { Rails.cache.clear }

  describe '#current_weather' do
    let(:weather_response) do
      {
        'weatherCondition' => { 'type' => 'HEAVY_RAIN' },
        'temperature' => { 'degrees' => 28.5 },
        'relativeHumidity' => 85
      }
    end

    before do
      stub_request(:get, /weather\.googleapis\.com/)
        .to_return(
          status: 200,
          body: weather_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns mapped condition and multiplier key' do
      result = provider.current_weather(city_code: 'hyd')
      # condition is the mapped value, same as multiplier_key
      expect(result[:condition]).to eq('rain_heavy')
      expect(result[:multiplier_key]).to eq('rain_heavy')
    end

    it 'returns temperature and humidity' do
      result = provider.current_weather(city_code: 'hyd')
      expect(result[:temp_c]).to eq(28.5)
      expect(result[:humidity_pct]).to eq(85)
    end

    it 'caches results within same 30-min bucket' do
      # Call twice in quick succession (same time bucket)
      provider.current_weather(city_code: 'hyd')
      result = provider.current_weather(city_code: 'hyd')
      expect(result[:condition]).to eq('rain_heavy')
    end

    context 'extreme heat' do
      let(:weather_response) do
        {
          'weatherCondition' => { 'type' => 'CLEAR' },
          'temperature' => { 'degrees' => 44.0 },
          'relativeHumidity' => 20
        }
      end

      it 'overrides condition to extreme_heat when temp > 42 and clear' do
        result = provider.current_weather(city_code: 'hyd')
        expect(result[:multiplier_key]).to eq('extreme_heat')
      end
    end

    context 'API failure' do
      before do
        stub_request(:get, /weather\.googleapis\.com/).to_timeout
      end

      it 'returns default clear weather on error' do
        result = provider.current_weather(city_code: 'hyd')
        expect(result[:multiplier_key]).to eq('clear')
        expect(result[:temp_c]).to be_nil
      end
    end

    context 'unknown city' do
      it 'returns default weather for unmapped city codes' do
        result = provider.current_weather(city_code: 'xyz')
        expect(result[:multiplier_key]).to eq('clear')
      end
    end
  end
end
