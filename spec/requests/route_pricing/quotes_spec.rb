# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Route Pricing Quotes API', type: :request do
  include_context 'pricing_setup'

  # Force-create pricing_config and its dependencies before request specs
  before do
    pricing_config # trigger lazy creation
    ENV['SERVICE_API_KEY'] = 'test-api-key-12345'
    ENV['PRICING_MODE'] = 'calibration'
    ENV['ROUTE_PROVIDER_STRATEGY'] = 'haversine'
    allow(PricingRolloutFlag).to receive(:enabled?).and_return(false)
    RoutePricing::Services::H3ZoneResolver.invalidate!(city_code)
    host! 'localhost'
  end

  after do
    ENV.delete('SERVICE_API_KEY')
    ENV.delete('PRICING_MODE')
    ENV.delete('ROUTE_PROVIDER_STRATEGY')
  end

  let(:headers) { { 'X-API-KEY' => 'test-api-key-12345', 'Content-Type' => 'application/json' } }

  describe 'POST /route_pricing/create_quote' do
    let(:params) do
      {
        city_code: city_code,
        vehicle_type: vehicle_type,
        pickup_lat: pickup_lat,
        pickup_lng: pickup_lng,
        drop_lat: drop_lat,
        drop_lng: drop_lng
      }
    end

    it 'returns a successful quote' do
      post '/route_pricing/create_quote', params: params.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['price_paise']).to be > 0
      expect(body['quote_id']).to be_present
    end

    it 'rejects requests without API key' do
      post '/route_pricing/create_quote', params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns error for missing pricing config' do
      params[:city_code] = 'nonexistent'
      params[:vehicle_type] = 'nonexistent'
      post '/route_pricing/create_quote', params: params.to_json, headers: headers
      expect(response.status).to be_in([404, 500])
    end
  end

  describe 'POST /route_pricing/multi_quote' do
    let(:params) do
      {
        city_code: city_code,
        pickup_lat: pickup_lat,
        pickup_lng: pickup_lng,
        drop_lat: drop_lat,
        drop_lng: drop_lng
      }
    end

    it 'returns quotes for available vehicle types' do
      post '/route_pricing/multi_quote', params: params.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['quotes']).to be_an(Array)
    end
  end

  describe 'POST /route_pricing/validate_quote' do
    let!(:quote) do
      create(:pricing_quote, city_code: city_code, vehicle_type: vehicle_type,
             valid_until: 15.minutes.from_now)
    end

    it 'validates an existing quote' do
      post '/route_pricing/validate_quote',
           params: { quote_id: quote.id }.to_json,
           headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['valid']).to be true
    end

    it 'returns not found for invalid quote_id' do
      post '/route_pricing/validate_quote',
           params: { quote_id: '00000000-0000-0000-0000-000000000000' }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
