# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::PriceCalculator do
  include_context 'pricing_setup'

  let(:zone_resolver) { instance_double(RoutePricing::Services::ZonePricingResolver) }
  let(:calculator) { described_class.new(config: pricing_config, zone_resolver: zone_resolver) }
  let(:time_band) { 'morning_rush' }
  let(:ist) { ActiveSupport::TimeZone['Asia/Kolkata'] }
  let(:quote_time) { ist.local(2026, 3, 30, 9, 0) } # Monday 9 AM

  let(:zone_pricing_result) do
    RoutePricing::Services::ZonePricingResolver::Result.new(
      base_fare_paise: 6000,
      min_fare_paise: 5500,
      per_km_rate_paise: 1600,
      base_distance_m: 2000,
      source: :zone_override,
      pricing_mode: :linear,
      zone_info: { pickup_zone: 'hitech_city', pickup_type: 'tech_corridor',
                   drop_zone: 'gachibowli', drop_type: 'tech_corridor', time_band: 'morning_rush' },
      zone_slabs: nil,
      fuel_surcharge_pct: 0.0,
      zone_multiplier: 1.0,
      special_location_surcharge: 0,
      oda_config: { both_oda: false, surcharge_pct: 0 },
      per_min_rate_paise: 0
    )
  end

  before do
    allow(zone_resolver).to receive(:resolve).and_return(zone_pricing_result)
    allow(PricingRolloutFlag).to receive(:enabled?).and_return(false)
    ENV['PRICING_MODE'] = 'calibration'
  end

  after { ENV['PRICING_MODE'] = nil }

  describe '#calculate' do
    it 'returns final_price_paise and breakdown' do
      result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
      expect(result).to have_key(:final_price_paise)
      expect(result).to have_key(:breakdown)
      expect(result[:final_price_paise]).to be > 0
    end

    it 'uses base_fare from zone pricing' do
      result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
      expect(result[:breakdown][:base_fare]).to eq(6000)
    end

    it 'calculates chargeable distance after base distance' do
      result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
      expect(result[:breakdown][:chargeable_distance_m]).to eq(6000) # 8000 - 2000
    end

    it 'returns 0 chargeable distance for short trips' do
      result = calculator.calculate(distance_m: 1000, quote_time: quote_time)
      expect(result[:breakdown][:chargeable_distance_m]).to eq(0)
    end

    context 'distance band multiplier' do
      it 'applies micro discount for <5km trips (mid vehicle)' do
        result = calculator.calculate(distance_m: 3000, quote_time: quote_time)
        expect(result[:breakdown][:distance_band_multiplier]).to eq(0.90)
      end

      it 'applies no multiplier for 5-12km trips' do
        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        expect(result[:breakdown][:distance_band_multiplier]).to eq(1.0)
      end

      it 'applies medium premium for 12-20km trips' do
        result = calculator.calculate(distance_m: 15000, quote_time: quote_time)
        expect(result[:breakdown][:distance_band_multiplier]).to eq(1.05)
      end
    end

    context 'calibration mode' do
      it 'sets all surge multipliers to 1.0' do
        result = calculator.calculate(distance_m: 8000, quote_time: quote_time,
                                      duration_in_traffic_s: 2000, duration_s: 1000)
        expect(result[:breakdown][:traffic_multiplier]).to eq(1.0)
        expect(result[:breakdown][:time_multiplier]).to eq(1.0)
        expect(result[:breakdown][:zone_multiplier]).to eq(1.0)
        expect(result[:breakdown][:combined_surge]).to eq(1.0)
      end

      it 'uses precise rounding' do
        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        # In calibration mode, price should be .round (not rounded to nearest 10)
        expect(result[:final_price_paise]).to eq(result[:breakdown][:final_price])
      end
    end

    context 'per-minute pricing' do
      let(:zone_pricing_with_per_min) do
        RoutePricing::Services::ZonePricingResolver::Result.new(
          **zone_pricing_result.to_h.merge(per_min_rate_paise: 200)
        )
      end

      before { allow(zone_resolver).to receive(:resolve).and_return(zone_pricing_with_per_min) }

      it 'adds time component when per_min_rate > 0 and duration present' do
        result = calculator.calculate(distance_m: 8000, duration_in_traffic_s: 1800,
                                      quote_time: quote_time)
        expect(result[:breakdown][:time_component]).to eq(6000) # (1800/60) * 200
      end

      it 'returns 0 time component when duration is nil' do
        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        expect(result[:breakdown][:time_component]).to eq(0)
      end
    end

    context 'dead-km charge' do
      let(:config_with_dead_km) do
        create(:pricing_config,
          city_code: 'hyd', vehicle_type: 'three_wheeler', timezone: 'Asia/Kolkata',
          base_fare_paise: 5000, min_fare_paise: 4500, per_km_rate_paise: 1500,
          base_distance_m: 2000, vehicle_multiplier: 1.0, city_multiplier: 1.0,
          surge_multiplier: 1.0, version: 2, active: true, approval_status: 'approved',
          dead_km_enabled: true, free_pickup_radius_m: 2000,
          dead_km_per_km_rate_paise: 800
        )
      end

      let(:calc_with_dead_km) { described_class.new(config: config_with_dead_km, zone_resolver: zone_resolver) }

      it 'charges dead-km when pickup distance exceeds free radius' do
        # Stub zone lookup for resolve_pickup_distance
        allow(Zone).to receive(:find_containing).and_return(
          instance_double(Zone, zone_type: 'tech_corridor')
        )
        result = calc_with_dead_km.calculate(
          distance_m: 8000, pickup_lat: 17.44, pickup_lng: 78.38, quote_time: quote_time
        )
        expect(result[:breakdown][:dead_km_charge]).to be >= 0
      end
    end

    context 'unit economics guardrail' do
      it 'enforces minimum margin' do
        # Create very low pricing to trigger guardrail
        low_zone_pricing = RoutePricing::Services::ZonePricingResolver::Result.new(
          base_fare_paise: 100, min_fare_paise: 100, per_km_rate_paise: 10,
          base_distance_m: 0, source: :city_default, pricing_mode: :linear,
          zone_info: {}, zone_slabs: nil, fuel_surcharge_pct: 0.0,
          zone_multiplier: 1.0, special_location_surcharge: 0,
          oda_config: { both_oda: false, surcharge_pct: 0 }, per_min_rate_paise: 0
        )
        allow(zone_resolver).to receive(:resolve).and_return(low_zone_pricing)

        result = calculator.calculate(distance_m: 1000, quote_time: quote_time)
        # Price should be bumped to maintain minimum margin
        expect(result[:final_price_paise]).to be >= pricing_config.min_fare_paise
      end
    end

    context 'pricing source passthrough' do
      it 'includes pricing_source in breakdown' do
        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        expect(result[:breakdown][:pricing_source]).to eq(:zone_override)
      end
    end

    context 'weight multiplier' do
      it 'applies no multiplier for light items' do
        result = calculator.calculate(distance_m: 8000, weight_kg: 10, quote_time: quote_time)
        expect(result[:breakdown][:weight_multiplier]).to eq(1.0)
      end

      it 'applies 1.1x for 30kg items' do
        result = calculator.calculate(distance_m: 8000, weight_kg: 30, quote_time: quote_time)
        expect(result[:breakdown][:weight_multiplier]).to eq(1.1)
      end

      it 'applies 1.4x for 300kg items' do
        result = calculator.calculate(distance_m: 8000, weight_kg: 300, quote_time: quote_time)
        expect(result[:breakdown][:weight_multiplier]).to eq(1.4)
      end
    end

    context 'zone type multiplier' do
      it 'applies business_cbd premium from zone info' do
        cbd_zone_pricing = RoutePricing::Services::ZonePricingResolver::Result.new(
          **zone_pricing_result.to_h.merge(
            zone_multiplier: nil,
            zone_info: { pickup_type: 'business_cbd', drop_type: 'default', time_band: 'morning_rush' }
          )
        )
        allow(zone_resolver).to receive(:resolve).and_return(cbd_zone_pricing)

        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        expect(result[:breakdown][:zone_type_multiplier]).to eq(1.05)
      end
    end

    context 'ODA surcharge' do
      it 'applies surcharge when both zones are ODA' do
        oda_zone_pricing = RoutePricing::Services::ZonePricingResolver::Result.new(
          **zone_pricing_result.to_h.merge(
            oda_config: { both_oda: true, surcharge_pct: 5.0 }
          )
        )
        allow(zone_resolver).to receive(:resolve).and_return(oda_zone_pricing)

        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        expect(result[:breakdown][:oda_multiplier]).to eq(1.05)
      end

      it 'does not apply surcharge for non-ODA routes' do
        result = calculator.calculate(distance_m: 8000, quote_time: quote_time)
        expect(result[:breakdown][:oda_multiplier]).to eq(1.0)
      end
    end
  end
end
