# frozen_string_literal: true

# =============================================================================
# H3 Surge Bucket Rake Tasks
# =============================================================================
# Manage per-hex surge pricing data for hyperlocal pricing.
#
# USAGE:
#   rails surge:seed_sample[hyd]
#   rails surge:cleanup
#   rails surge:summary[hyd]
# =============================================================================

namespace :surge do
  desc "Seed sample surge data for testing (around HITEC City, Hyderabad)"
  task :seed_sample, [:city_code] => :environment do |_, args|
    city_code = args[:city_code] || 'hyd'

    unless defined?(H3)
      puts "H3 gem not available. Run: bundle install"
      exit 1
    end

    # HITEC City center: 17.4435, 78.3772
    hitec_city_lat = 17.4435
    hitec_city_lng = 78.3772

    # Gachibowli: 17.4401, 78.3489
    gachibowli_lat = 17.4401
    gachibowli_lng = 78.3489

    # Madhapur: 17.4486, 78.3908
    madhapur_lat = 17.4486
    madhapur_lng = 78.3908

    sample_points = [
      { name: "HITEC City", lat: hitec_city_lat, lng: hitec_city_lng, surge: 1.5, demand: 80, supply: 40 },
      { name: "Gachibowli", lat: gachibowli_lat, lng: gachibowli_lng, surge: 1.3, demand: 60, supply: 50 },
      { name: "Madhapur", lat: madhapur_lat, lng: madhapur_lng, surge: 1.2, demand: 55, supply: 60 }
    ]

    created = 0
    time_bands = [nil, 'morning', 'afternoon', 'evening']

    sample_points.each do |point|
      h3_r9 = H3.from_geo_coordinates([point[:lat], point[:lng]], 9).to_s(16)

      # Also get neighboring hexes for a realistic cluster
      center_hex = H3.from_geo_coordinates([point[:lat], point[:lng]], 9)
      ring_hexes = H3.k_ring(center_hex, 1)

      ring_hexes.each_with_index do |hex, idx|
        hex_str = hex.to_s(16)
        # Decay surge away from center
        decay = 1.0 - (idx * 0.05)

        time_bands.each do |band|
          # Evening surge is higher
          band_boost = case band
                       when 'evening' then 1.2
                       when 'morning' then 1.1
                       else 1.0
                       end

          effective_surge = [(point[:surge] * decay * band_boost).round(2), 1.0].max

          bucket = H3SurgeBucket.find_or_initialize_by(
            h3_index: hex_str,
            city_code: city_code,
            time_band: band
          )

          bucket.assign_attributes(
            h3_resolution: 9,
            surge_multiplier: effective_surge,
            demand_score: [(point[:demand] * decay).round(1), 0].max,
            supply_score: [(point[:supply] * (2.0 - decay)).round(1), 100].min,
            source: 'manual',
            expires_at: nil,
            metadata: { area_name: point[:name], seeded: true }
          )

          bucket.save!
          created += 1
        end
      end

      puts "  #{point[:name]}: #{ring_hexes.size} hexes x #{time_bands.size} time bands"
    end

    puts "\nDone! Created/updated #{created} surge buckets for #{city_code}"
  end

  desc "Clear expired surge buckets"
  task cleanup: :environment do
    deleted = H3SurgeBucket.where('expires_at < ?', Time.current).delete_all
    puts "Cleared #{deleted} expired surge buckets"
  end

  desc "Show surge summary for a city"
  task :summary, [:city_code] => :environment do |_, args|
    city = args[:city_code] || 'hyd'
    resolver = RoutePricing::Services::H3SurgeResolver.new(city)

    puts "Surge summary for #{city}:"
    puts "=" * 40

    # Overall summary
    summary = resolver.city_surge_summary
    summary.each { |k, v| puts "  #{k}: #{v}" }

    # Per time band
    %w[morning afternoon evening].each do |band|
      band_summary = resolver.city_surge_summary(time_band: band)
      if band_summary[:total_hexes] > 0
        puts "\n  #{band}:"
        band_summary.each { |k, v| puts "    #{k}: #{v}" }
      end
    end
  end
end
