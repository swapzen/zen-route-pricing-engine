# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::RouteResolver do
  let(:resolver) { described_class.new }
  let(:pickup_lat) { 17.4435 }
  let(:pickup_lng) { 78.3772 }
  let(:drop_lat) { 17.4401 }
  let(:drop_lng) { 78.3489 }

  let(:google_distance_matrix_response) do
    {
      'rows' => [{
        'elements' => [{
          'distance' => { 'value' => 8000 },
          'duration' => { 'value' => 1200 },
          'duration_in_traffic' => { 'value' => 1500 },
          'status' => 'OK'
        }]
      }],
      'status' => 'OK'
    }
  end

  before do
    stub_request(:get, /maps\.googleapis\.com\/maps\/api\/distancematrix/)
      .to_return(
        status: 200,
        body: google_distance_matrix_response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:get, /maps\.googleapis\.com\/maps\/api\/directions/)
      .to_return(
        status: 200,
        body: {
          status: 'OK',
          routes: [{
            legs: [{
              distance: { value: 8000 },
              duration: { value: 1200 },
              duration_in_traffic: { value: 1500 },
              steps: [{ start_location: { lat: pickup_lat, lng: pickup_lng },
                        end_location: { lat: drop_lat, lng: drop_lng },
                        distance: { value: 8000 }, duration: { value: 1200 } }]
            }]
          }]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Use memory store so caching tests work (dev may use null_store)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after do
    Rails.cache = @original_cache
  end

  describe '#resolve' do
    it 'returns distance, duration, and provider info' do
      result = resolver.resolve(
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng,
        city_code: 'hyd', vehicle_type: 'three_wheeler'
      )
      expect(result[:distance_m]).to eq(8000)
      expect(result[:duration_s]).to eq(1200)
      expect(result[:provider]).to eq('google')
    end

    it 'caches subsequent calls' do
      resolver.resolve(
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng,
        city_code: 'hyd', vehicle_type: 'three_wheeler'
      )

      result = resolver.resolve(
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng,
        city_code: 'hyd', vehicle_type: 'three_wheeler'
      )
      expect(result[:cache_hit]).to be true
    end

    context 'when Google Maps API fails' do
      before do
        stub_request(:get, /maps\.googleapis\.com/)
          .to_timeout
      end

      it 'falls back to haversine calculation' do
        result = resolver.resolve(
          pickup_lat: pickup_lat, pickup_lng: pickup_lng,
          drop_lat: drop_lat, drop_lng: drop_lng,
          city_code: 'hyd', vehicle_type: 'three_wheeler'
        )
        expect(result[:distance_m]).to be > 0
        expect(result[:provider]).to include('haversine')
      end
    end

    it 'normalizes coordinates before lookup' do
      result = resolver.resolve(
        pickup_lat: '17.4435', pickup_lng: '78.3772',
        drop_lat: '17.4401', drop_lng: '78.3489',
        city_code: 'hyd', vehicle_type: 'three_wheeler'
      )
      expect(result[:pickup_norm]).to be_present
      expect(result[:drop_norm]).to be_present
    end
  end

  describe '#resolve_with_segments' do
    it 'returns steps along with distance data' do
      result = resolver.resolve_with_segments(
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng,
        city_code: 'hyd', vehicle_type: 'three_wheeler'
      )
      expect(result[:distance_m]).to eq(8000)
    end

    context 'when directions API fails' do
      before do
        stub_request(:get, /maps\.googleapis\.com\/maps\/api\/directions/)
          .to_timeout
      end

      it 'falls back to standard resolve' do
        result = resolver.resolve_with_segments(
          pickup_lat: pickup_lat, pickup_lng: pickup_lng,
          drop_lat: drop_lat, drop_lng: drop_lng,
          city_code: 'hyd', vehicle_type: 'three_wheeler'
        )
        expect(result[:distance_m]).to be > 0
      end
    end
  end
end
