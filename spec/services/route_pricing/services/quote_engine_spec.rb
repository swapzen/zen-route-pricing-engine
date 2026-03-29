# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::QuoteEngine do
  include_context 'pricing_setup'

  let(:mock_route_resolver) { instance_double(RoutePricing::Services::RouteResolver) }
  let(:engine) { described_class.new(route_resolver: mock_route_resolver) }

  let(:route_result) do
    {
      distance_m: 8000,
      duration_s: 1200,
      duration_in_traffic_s: 1500,
      provider: 'google',
      cache_hit: false,
      cache_key: "route:v1:#{city_code}:#{vehicle_type}:17.44,78.37:17.44,78.32:t4",
      pickup_norm: { lat: 17.44, lng: 78.37 },
      drop_norm: { lat: 17.44, lng: 78.32 }
    }
  end

  before do
    allow(mock_route_resolver).to receive(:resolve).and_return(route_result)
    allow(mock_route_resolver).to receive(:resolve_with_segments).and_return(route_result)
    allow(PricingRolloutFlag).to receive(:enabled?).and_return(false)
    ENV['PRICING_MODE'] = 'calibration'
    RoutePricing::Services::H3ZoneResolver.invalidate!(city_code)
  end

  after { ENV['PRICING_MODE'] = nil }

  describe '#create_quote' do
    it 'returns a successful quote with price' do
      result = engine.create_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:success]).to be true
      expect(result[:price_paise]).to be > 0
      expect(result[:distance_m]).to eq(8000)
      expect(result[:quote_id]).to be_present
    end

    it 'returns breakdown in response' do
      result = engine.create_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:breakdown]).to be_a(Hash)
      expect(result[:breakdown][:pricing_source]).to be_present
    end

    it 'persists quote in database' do
      expect {
        engine.create_quote(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: pickup_lat, pickup_lng: pickup_lng,
          drop_lat: drop_lat, drop_lng: drop_lng
        )
      }.to change(PricingQuote, :count).by(1)
    end

    it 'returns error when pricing config missing' do
      result = engine.create_quote(
        city_code: 'nonexistent', vehicle_type: 'nonexistent',
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:error]).to be_present
      expect(result[:code]).to eq(404)
    end

    it 'includes valid_until in response' do
      result = engine.create_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:valid_until]).to be_present
      expect(result[:expires_in_seconds]).to be > 0
    end
  end

  describe '#create_multi_quote' do
    it 'returns quotes for available vehicle types' do
      # Use test city — config already exists from pricing_setup
      result = engine.create_multi_quote(
        city_code: city_code,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:success]).to be true
      expect(result[:quotes]).to be_an(Array)
      expect(result[:quotes].size).to be >= 1
    end
  end

  describe '#create_round_trip_quote' do
    it 'returns outbound and return quotes' do
      result = engine.create_round_trip_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:success]).to be true
      expect(result[:outbound]).to be_present
      expect(result[:round_trip_summary][:discounted_total_paise]).to be > 0
    end
  end

  describe 'merchant policy application' do
    let!(:merchant_policy) do
      MerchantPricingPolicy.create!(
        merchant_id: 'test_merchant_123', policy_type: 'markup_pct',
        value_pct: 10.0, priority: 1, active: true
      )
    end

    it 'applies merchant markup when merchant_id provided' do
      base_result = engine.create_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )

      merchant_result = engine.create_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng,
        merchant_id: 'test_merchant_123'
      )

      expect(merchant_result[:price_paise]).to be >= base_result[:price_paise]
    end
  end

  describe 'error handling' do
    it 'returns 500 on unexpected errors' do
      allow(mock_route_resolver).to receive(:resolve).and_raise(StandardError, 'test error')

      result = engine.create_quote(
        city_code: city_code, vehicle_type: vehicle_type,
        pickup_lat: pickup_lat, pickup_lng: pickup_lng,
        drop_lat: drop_lat, drop_lng: drop_lng
      )
      expect(result[:error]).to be_present
      expect(result[:code]).to eq(500)
    end
  end
end
