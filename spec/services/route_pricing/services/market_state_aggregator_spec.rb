# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::MarketStateAggregator do
  let(:city_code) { 'tst' }
  let(:aggregator) { described_class.new(city_code: city_code, lookback_hours: 24) }

  describe '#dashboard' do
    context 'with no outcomes' do
      it 'returns empty dashboard' do
        result = aggregator.dashboard
        expect(result[:city_code]).to eq(city_code)
        expect(result[:overall]).to be_present
      end
    end

    context 'with outcomes' do
      before do
        3.times do
          quote = create(:pricing_quote, city_code: city_code)
          create(:pricing_outcome, pricing_quote: quote, city_code: city_code,
                 outcome: 'accepted', vehicle_type: 'three_wheeler')
        end
        2.times do
          quote = create(:pricing_quote, city_code: city_code)
          create(:pricing_outcome, pricing_quote: quote, city_code: city_code,
                 outcome: 'rejected', vehicle_type: 'three_wheeler')
        end
      end

      it 'returns overall metrics with acceptance rate' do
        result = aggregator.dashboard
        expect(result[:overall][:total_quotes]).to eq(5)
      end

      it 'includes vehicle breakdown' do
        result = aggregator.dashboard
        expect(result[:by_vehicle]).to be_present
      end
    end
  end

  describe '#zone_health' do
    before do
      2.times do
        quote = create(:pricing_quote, city_code: city_code)
        create(:pricing_outcome, pricing_quote: quote, city_code: city_code,
               outcome: 'accepted', pickup_zone_code: 'tst_zone')
      end
      quote = create(:pricing_quote, city_code: city_code)
      create(:pricing_outcome, pricing_quote: quote, city_code: city_code,
             outcome: 'rejected', pickup_zone_code: 'tst_zone')
    end

    it 'returns zone-level acceptance metrics' do
      result = aggregator.zone_health
      expect(result).to be_an(Array)
      zone = result.find { |z| z[:zone_code] == 'tst_zone' }
      expect(zone[:total_quotes]).to eq(3)
    end
  end

  describe '#pressure_map' do
    it 'returns empty array when no outcomes exist' do
      result = aggregator.pressure_map
      expect(result).to be_an(Array)
    end
  end
end
