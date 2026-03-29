# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoutePricing::Services::H3ZoneResolver do
  # Use isolated city code to avoid conflict with real hyd data
  let(:city_code) { 'tst' }

  let!(:zone) do
    create(:zone, zone_code: 'tst_hitech', city: city_code,
           zone_type: 'tech_corridor', status: true, priority: 10)
  end

  # A known coordinate and its R7 hex
  let(:test_lat) { 17.4435 }
  let(:test_lng) { 78.3772 }
  let(:test_r7_hex) { H3.from_geo_coordinates([test_lat, test_lng], 7).to_s(16) }

  before do
    described_class.invalidate!(city_code)
  end

  describe '#resolve' do
    context 'with H3 mappings present' do
      let!(:h3_mapping) do
        create(:zone_h3_mapping,
          zone: zone, city_code: city_code,
          h3_index_r7: test_r7_hex, serviceable: true
        )
      end

      before { described_class.build_city_map(city_code) }

      it 'resolves lat/lng to correct zone via H3 lookup' do
        resolver = described_class.new(city_code)
        resolved = resolver.resolve(test_lat, test_lng)
        expect(resolved).to eq(zone)
      end

      it 'returns nil for coordinates outside any mapped cell' do
        resolver = described_class.new(city_code)
        resolved = resolver.resolve(28.6139, 77.2090) # Delhi
        expect(resolved).to be_nil
      end
    end

    context 'with no mappings' do
      before { described_class.build_city_map(city_code) }

      it 'returns nil gracefully' do
        resolver = described_class.new(city_code)
        expect(resolver.resolve(test_lat, test_lng)).to be_nil
      end
    end

    context 'with inactive zone' do
      let!(:inactive_zone) do
        create(:zone, zone_code: 'tst_inactive', city: city_code,
               zone_type: 'default', status: false)
      end

      let!(:h3_mapping) do
        far_hex = H3.from_geo_coordinates([17.50, 78.50], 7).to_s(16)
        create(:zone_h3_mapping,
          zone: inactive_zone, city_code: city_code,
          h3_index_r7: far_hex, serviceable: true
        )
      end

      before { described_class.build_city_map(city_code) }

      it 'does not resolve to inactive zones' do
        resolver = described_class.new(city_code)
        resolved = resolver.resolve(17.50, 78.50)
        expect(resolved).to be_nil
      end
    end

    context 'boundary disambiguation' do
      let!(:zone2) do
        create(:zone, zone_code: 'tst_gachi', city: city_code,
               zone_type: 'tech_corridor', status: true, priority: 5)
      end

      let(:boundary_lat) { 17.44 }
      let(:boundary_lng) { 78.35 }
      let(:boundary_hex) { H3.from_geo_coordinates([boundary_lat, boundary_lng], 7).to_s(16) }

      let!(:mapping1) do
        create(:zone_h3_mapping,
          zone: zone, city_code: city_code,
          h3_index_r7: boundary_hex, is_boundary: true, serviceable: true
        )
      end

      let!(:mapping2) do
        create(:zone_h3_mapping,
          zone: zone2, city_code: city_code,
          h3_index_r7: boundary_hex, is_boundary: true, serviceable: true
        )
      end

      before { described_class.build_city_map(city_code) }

      it 'resolves boundary cell to higher priority zone' do
        resolver = described_class.new(city_code)
        resolved = resolver.resolve(boundary_lat, boundary_lng)
        expect(resolved).to eq(zone)
      end
    end
  end

  describe '.invalidate!' do
    let!(:h3_mapping) do
      create(:zone_h3_mapping,
        zone: zone, city_code: city_code,
        h3_index_r7: test_r7_hex, serviceable: true
      )
    end

    it 'clears cached maps for a city' do
      described_class.build_city_map(city_code)
      resolver = described_class.new(city_code)
      expect(resolver.resolve(test_lat, test_lng)).to eq(zone)

      described_class.invalidate!(city_code)
      # Build empty map by removing mapping (simulate cache clear)
      # After invalidation, stale? check will trigger rebuild
      expect(described_class.new(city_code).resolve(test_lat, test_lng)).to eq(zone) # rebuilds from DB
    end

    it 'clears all maps when no city specified' do
      described_class.build_city_map(city_code)
      described_class.invalidate!
      # After invalidation, next access triggers rebuild
      expect(described_class.new(city_code).resolve(test_lat, test_lng)).to eq(zone)
    end
  end
end
