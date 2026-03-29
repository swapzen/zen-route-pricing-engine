# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::ZonePricingResolver do
  include_context 'pricing_setup'

  let(:resolver) { described_class.new }

  before do
    described_class.reset_inter_zone_config_cache!
    RoutePricing::Services::H3ZoneResolver.invalidate!(city_code)
  end

  describe '#resolve' do
    context 'corridor override (tier 1)' do
      it 'returns corridor pricing when both zones matched and pair exists' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,  # inside pickup_zone bbox
          drop_lat: 17.44, drop_lng: 78.32,       # inside drop_zone bbox
          time_band: 'morning_rush'
        )
        expect(result.source).to eq(:corridor_override)
        expect(result.base_fare_paise).to eq(corridor_pricing.base_fare_paise)
        expect(result.pricing_mode).to eq(:linear)
      end
    end

    context 'inter-zone formula (tier 2)' do
      let(:far_drop_zone) do
        create(:zone, zone_code: 'tst_kondapur', city: city_code,
               zone_type: 'residential_dense', status: true, priority: 10,
               lat_min: 17.46, lat_max: 17.50, lng_min: 78.35, lng_max: 78.40)
      end

      let!(:far_drop_zvp) do
        create(:zone_vehicle_pricing,
          zone: far_drop_zone, city_code: city_code, vehicle_type: vehicle_type,
          base_fare_paise: 5000, min_fare_paise: 4500, per_km_rate_paise: 1400,
          base_distance_m: 2000, active: true
        )
      end

      it 'returns inter-zone weighted average when zones differ and no corridor' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,   # pickup_zone
          drop_lat: 17.48, drop_lng: 78.37,        # far_drop_zone
          time_band: 'morning_rush'
        )
        expect(result.source).to eq(:inter_zone_formula)
        expect(result.pricing_mode).to eq(:linear)
      end
    end

    context 'zone-time override (tier 3)' do
      it 'returns zone-time pricing for intra-zone with time band' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,   # inside pickup_zone
          drop_lat: 17.45, drop_lng: 78.38,        # also inside pickup_zone
          time_band: 'morning_rush'
        )
        expect(result.source).to eq(:zone_time_override)
        expect(result.base_fare_paise).to eq(zone_time_pricing.base_fare_paise)
      end
    end

    context 'zone override (tier 4)' do
      it 'returns base zone pricing when no time-band match' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,
          drop_lat: 17.45, drop_lng: 78.38,
          time_band: 'midday'
        )
        expect(result.source).to eq(:zone_override)
        expect(result.base_fare_paise).to eq(zone_vehicle_pricing.base_fare_paise)
      end
    end

    context 'city default (tier 5)' do
      it 'returns city default when no zone matched' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 0, pickup_lng: 0,
          drop_lat: 0, drop_lng: 0,
          time_band: 'morning_rush'
        )
        expect(result.source).to eq(:city_default)
        expect(result.base_fare_paise).to eq(pricing_config.base_fare_paise)
      end
    end

    context 'nil zones' do
      it 'handles nil zones gracefully' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 0, pickup_lng: 0,
          drop_lat: 0, drop_lng: 0,
          time_band: 'morning_rush'
        )
        expect(result).to be_a(described_class::Result)
        expect(result.source).to eq(:city_default)
      end
    end

    context 'zone_info metadata' do
      it 'includes pickup/drop zone codes in zone_info' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,
          drop_lat: 17.45, drop_lng: 78.38,
          time_band: 'morning_rush'
        )
        expect(result.zone_info[:pickup_zone]).to eq('tst_pickup')
        expect(result.zone_info[:time_band]).to eq('morning_rush')
      end
    end

    context 'corridor bypasses zone multipliers' do
      it 'sets zone_multiplier to 1.0 for corridor pricing' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,
          drop_lat: 17.44, drop_lng: 78.32,
          time_band: 'morning_rush'
        )
        expect(result.zone_multiplier).to eq(1.0)
        expect(result.fuel_surcharge_pct).to eq(0.0)
      end
    end

    context 'time-band corridor' do
      let!(:time_corridor) do
        create(:zone_pair_vehicle_pricing,
          from_zone: pickup_zone, to_zone: drop_zone,
          city_code: city_code, vehicle_type: vehicle_type,
          base_fare_paise: 7500, min_fare_paise: 7000, per_km_rate_paise: 1900,
          active: true, time_band: 'evening_rush'
        )
      end

      it 'matches time-band-specific corridor over all-day corridor' do
        result = resolver.resolve(
          city_code: city_code, vehicle_type: vehicle_type,
          pickup_lat: 17.44, pickup_lng: 78.37,
          drop_lat: 17.44, drop_lng: 78.32,
          time_band: 'evening_rush'
        )
        expect(result.source).to eq(:corridor_override)
        expect(result.base_fare_paise).to eq(7500)
      end
    end
  end
end
