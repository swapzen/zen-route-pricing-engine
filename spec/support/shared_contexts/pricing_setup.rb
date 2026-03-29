# frozen_string_literal: true

# Uses city_code 'tst' (test) to avoid conflicts with existing hyd data in shared DB
RSpec.shared_context 'pricing_setup' do
  let(:city_code) { 'tst' }
  let(:vehicle_type) { 'three_wheeler' }
  let(:timezone) { 'Asia/Kolkata' }

  let(:pricing_config) do
    create(:pricing_config,
      city_code: city_code,
      vehicle_type: vehicle_type,
      timezone: timezone,
      base_fare_paise: 5000,
      min_fare_paise: 4500,
      per_km_rate_paise: 1500,
      base_distance_m: 2000,
      vehicle_multiplier: 1.0,
      city_multiplier: 1.0,
      surge_multiplier: 1.0,
      active: true,
      approval_status: 'approved'
    )
  end

  let(:distance_slab_1) do
    create(:pricing_distance_slab,
      pricing_config: pricing_config,
      min_distance_m: 0,
      max_distance_m: 5000,
      per_km_rate_paise: 1500
    )
  end

  let(:distance_slab_2) do
    create(:pricing_distance_slab,
      pricing_config: pricing_config,
      min_distance_m: 5000,
      max_distance_m: 15000,
      per_km_rate_paise: 1200
    )
  end

  let(:distance_slab_3) do
    create(:pricing_distance_slab,
      pricing_config: pricing_config,
      min_distance_m: 15000,
      max_distance_m: nil,
      per_km_rate_paise: 1000
    )
  end

  let!(:distance_slabs) { [distance_slab_1, distance_slab_2, distance_slab_3] }

  let(:pickup_zone) do
    create(:zone,
      zone_code: 'tst_pickup',
      city: city_code,
      zone_type: 'tech_corridor',
      status: true,
      priority: 10,
      lat_min: 17.42, lat_max: 17.46,
      lng_min: 78.35, lng_max: 78.40
    )
  end

  let(:drop_zone) do
    create(:zone,
      zone_code: 'tst_drop',
      city: city_code,
      zone_type: 'tech_corridor',
      status: true,
      priority: 10,
      lat_min: 17.42, lat_max: 17.46,
      lng_min: 78.30, lng_max: 78.35
    )
  end

  let!(:pickup_h3_mapping) do
    create(:zone_h3_mapping,
      zone: pickup_zone,
      city_code: city_code,
      h3_index_r7: '871964a4dffffff'
    )
  end

  let!(:drop_h3_mapping) do
    create(:zone_h3_mapping,
      zone: drop_zone,
      city_code: city_code,
      h3_index_r7: '871964a4effffff'
    )
  end

  let!(:zone_vehicle_pricing) do
    create(:zone_vehicle_pricing,
      zone: pickup_zone,
      city_code: city_code,
      vehicle_type: vehicle_type,
      base_fare_paise: 6000,
      min_fare_paise: 5500,
      per_km_rate_paise: 1600,
      base_distance_m: 2000,
      active: true
    )
  end

  let!(:zone_time_pricing) do
    create(:zone_vehicle_time_pricing,
      zone_vehicle_pricing: zone_vehicle_pricing,
      time_band: 'morning_rush',
      base_fare_paise: 6500,
      min_fare_paise: 6000,
      per_km_rate_paise: 1700,
      active: true
    )
  end

  let!(:corridor_pricing) do
    create(:zone_pair_vehicle_pricing,
      from_zone: pickup_zone,
      to_zone: drop_zone,
      city_code: city_code,
      vehicle_type: vehicle_type,
      base_fare_paise: 7000,
      min_fare_paise: 6500,
      per_km_rate_paise: 1800,
      active: true,
      time_band: nil
    )
  end

  # Coordinates within pickup_zone bbox
  let(:pickup_lat) { 17.44 }
  let(:pickup_lng) { 78.37 }
  # Coordinates within drop_zone bbox
  let(:drop_lat) { 17.44 }
  let(:drop_lng) { 78.32 }
end
