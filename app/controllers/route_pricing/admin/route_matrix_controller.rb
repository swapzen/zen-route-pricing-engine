# frozen_string_literal: true

require 'csv'

module RoutePricing
  module Admin
    class RouteMatrixController < ApplicationController
      VEHICLES = %w[two_wheeler scooter mini_3w three_wheeler tata_ace pickup_8ft canter_14ft].freeze
      TIME_BANDS = RoutePricing::Services::TimeBandResolver.all_bands.freeze

      # GET /route_pricing/admin/route_matrix
      # Returns route pricing matrix from recent simulation data
      def index
        city_code = params[:city_code] || 'hyd'
        time_band = params[:time_band] || 'morning_rush'
        vehicle_filter = params[:vehicle_type]
        distance_filter = params[:distance_category]
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i

        # Prefer landmark CSV (has addresses + 8 bands), fallback to legacy
        csv_path = Rails.root.join('tmp', 'simulation_landmarks.csv')
        csv_path = Rails.root.join('tmp', 'simulation_combined.csv') unless File.exist?(csv_path)

        unless File.exist?(csv_path)
          return render json: {
            success: false,
            error: 'No simulation data. Run script/simulate_landmark_routes.rb first.'
          }, status: :not_found
        end

        rows = []
        CSV.foreach(csv_path, headers: true) do |row|
          next if time_band.present? && row['time_band'] != time_band
          next if vehicle_filter.present? && row['vehicle_type'] != vehicle_filter
          next if distance_filter.present? && row['distance_category'].present? && row['distance_category'] != distance_filter
          rows << row
        end

        # Group by route — use landmark IDs if available, else zone codes
        route_groups = rows.group_by { |r|
          if r['pickup_landmark'].present?
            "#{r['pickup_landmark']}→#{r['drop_landmark']}"
          else
            "#{r['pickup_zone']}→#{r['drop_zone']}"
          end
        }

        matrix = route_groups.map do |route_key, route_rows|
          first = route_rows.first
          vehicle_prices = {}

          route_rows.each do |r|
            vehicle_prices[r['vehicle_type']] = {
              price_inr: r['price_inr'].to_i,
              price_paise: r['price_paise'].to_i,
              vendor_paise: r['vendor_paise'].to_i,
              margin_pct: r['margin_pct'].to_f
            }
          end

          {
            route_key: route_key,
            route_id: first['route_id'],
            pickup_address: first['pickup_address'],
            drop_address: first['drop_address'],
            pickup_zone: first['pickup_zone'],
            drop_zone: first['drop_zone'],
            pickup_lat: first['pickup_lat'],
            pickup_lng: first['pickup_lng'],
            drop_lat: first['drop_lat'],
            drop_lng: first['drop_lng'],
            route_type: first['route_type'],
            distance_m: first['distance_m'].to_i,
            distance_km: (first['distance_m'].to_f / 1000).round(1),
            distance_category: first['distance_category'],
            time_band: first['time_band'],
            vehicle_prices: vehicle_prices
          }
        end

        matrix.sort_by! { |r| r[:distance_km] }

        total = matrix.size
        offset = (page - 1) * per_page
        paginated = matrix[offset, per_page] || []

        all_prices = rows.map { |r| r['price_inr'].to_i }
        stats = if all_prices.any?
                  {
                    total_routes: total,
                    total_scenarios: rows.size,
                    unique_pickup_zones: rows.map { |r| r['pickup_zone'] }.uniq.compact.size,
                    unique_drop_zones: rows.map { |r| r['drop_zone'] }.uniq.compact.size,
                    avg_distance_km: (rows.map { |r| r['distance_m'].to_i }.sum.to_f / [rows.size, 1].max / 1000).round(1),
                    price_range_inr: { min: all_prices.min, max: all_prices.max, avg: (all_prices.sum.to_f / [all_prices.size, 1].max).round },
                    vehicles: VEHICLES,
                    time_bands: TIME_BANDS
                  }
                else
                  { total_routes: 0, vehicles: VEHICLES, time_bands: TIME_BANDS }
                end

        render json: {
          success: true,
          stats: stats,
          routes: paginated,
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end

      # POST /route_pricing/admin/route_matrix/generate_quote
      # Generate a fresh quote for a specific route
      def generate_quote
        engine = RoutePricing::Services::QuoteEngine.new

        quote_time = band_to_quote_time(params[:time_band])

        results = {}
        vehicles = params[:vehicle_type].present? ? [params[:vehicle_type]] : VEHICLES

        vehicles.each do |vt|
          result = engine.create_quote(
            pickup_lat: params[:pickup_lat].to_f,
            pickup_lng: params[:pickup_lng].to_f,
            drop_lat: params[:drop_lat].to_f,
            drop_lng: params[:drop_lng].to_f,
            vehicle_type: vt,
            city_code: params[:city_code] || 'hyd',
            quote_time: quote_time,
            include_inactive: true
          )

          if result[:success]
            results[vt] = {
              price_paise: result[:price_paise],
              price_inr: (result[:price_paise].to_f / 100).round,
              distance_m: result[:distance_m],
              pricing_source: result[:breakdown]&.dig(:pricing_source),
              confidence: result[:confidence]
            }
          else
            results[vt] = { error: result[:error] }
          end
        end

        render json: { success: true, quotes: results }
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      # GET /route_pricing/admin/route_matrix/calibration_routes
      # Returns the 10 calibrated competitor benchmark routes with current prices
      def calibration_routes
        time_band = params[:time_band] || 'morning_rush'
        quote_time = band_to_quote_time(time_band)

        calibration = [
          { name: 'Gowlidoddi → Storable', from: [17.4293, 78.3370], to: [17.4394, 78.3577], dist_label: '7.3km' },
          { name: 'Gowlidoddi → DispatchTrack', from: [17.4293, 78.3370], to: [17.4406, 78.3499], dist_label: '6.8km' },
          { name: 'LB Nagar → TCS Synergy', from: [17.3515, 78.5530], to: [17.3817, 78.4801], dist_label: '32.6km' },
          { name: 'Gowlidoddi → Ameerpet Metro', from: [17.4293, 78.3370], to: [17.4379, 78.4482], dist_label: '15.9km' },
          { name: 'LB Nagar → Shantiniketan', from: [17.3667, 78.5167], to: [17.3700, 78.5180], dist_label: '1.4km' },
          { name: 'Ameerpet → Nexus Mall', from: [17.4379, 78.4482], to: [17.4900, 78.3900], dist_label: '10.2km' },
          { name: 'JNTU → Charminar', from: [17.4900, 78.3900], to: [17.3616, 78.4747], dist_label: '24.6km' },
          { name: 'Vanasthali → Charminar', from: [17.4000, 78.5000], to: [17.3616, 78.4747], dist_label: '13.2km' },
          { name: 'AMB Cinemas → Ayyappa Society', from: [17.4480, 78.3900], to: [17.4500, 78.4000], dist_label: '4.9km' },
          { name: 'Ayyappa Society → Gowlidoddi', from: [17.4500, 78.4000], to: [17.4293, 78.3370], dist_label: '8.1km' }
        ]

        engine = RoutePricing::Services::QuoteEngine.new
        routes = []

        calibration.each do |route|
          vehicle_prices = {}

          VEHICLES.each do |vt|
            result = engine.create_quote(
              pickup_lat: route[:from][0],
              pickup_lng: route[:from][1],
              drop_lat: route[:to][0],
              drop_lng: route[:to][1],
              vehicle_type: vt,
              city_code: 'hyd',
              quote_time: quote_time,
              include_inactive: true
            )

            if result[:success]
              vehicle_prices[vt] = {
                price_inr: (result[:price_paise].to_f / 100).round,
                distance_m: result[:distance_m]
              }
            end
          end

          routes << {
            name: route[:name],
            dist_label: route[:dist_label],
            pickup_lat: route[:from][0],
            pickup_lng: route[:from][1],
            drop_lat: route[:to][0],
            drop_lng: route[:to][1],
            time_band: time_band,
            vehicle_prices: vehicle_prices
          }
        end

        render json: { success: true, routes: routes, time_band: time_band, vehicles: VEHICLES }
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      # GET /route_pricing/admin/route_matrix/landmark_routes
      # Returns landmark-based routes with real addresses
      def landmark_routes
        time_band = params[:time_band] || 'morning_rush'
        distance_filter = params[:distance_category]
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i

        csv_path = Rails.root.join('tmp', 'simulation_landmarks.csv')
        unless File.exist?(csv_path)
          return render json: {
            success: false,
            error: 'No landmark simulation data. Run script/simulate_landmark_routes.rb first.'
          }, status: :not_found
        end

        rows = []
        CSV.foreach(csv_path, headers: true) do |row|
          next if time_band.present? && row['time_band'] != time_band
          next if distance_filter.present? && row['distance_category'] != distance_filter
          rows << row
        end

        route_groups = rows.group_by { |r| "#{r['pickup_landmark']}→#{r['drop_landmark']}" }

        matrix = route_groups.map do |route_key, route_rows|
          first = route_rows.first
          vehicle_prices = {}
          route_rows.each do |r|
            vehicle_prices[r['vehicle_type']] = {
              price_inr: r['price_inr'].to_i,
              price_paise: r['price_paise'].to_i
            }
          end

          {
            route_key: route_key,
            pickup_address: first['pickup_address'],
            drop_address: first['drop_address'],
            pickup_zone: first['pickup_zone'],
            drop_zone: first['drop_zone'],
            distance_m: first['distance_m'].to_i,
            distance_km: (first['distance_m'].to_f / 1000).round(1),
            distance_category: first['distance_category'],
            time_band: first['time_band'],
            vehicle_prices: vehicle_prices
          }
        end

        matrix.sort_by! { |r| r[:distance_km] }
        total = matrix.size
        offset = (page - 1) * per_page
        paginated = matrix[offset, per_page] || []

        render json: {
          success: true,
          routes: paginated,
          time_band: time_band,
          vehicles: VEHICLES,
          time_bands: TIME_BANDS,
          pagination: { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil }
        }
      rescue StandardError => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end

      private

      BAND_TIMES = {
        'early_morning' => { time: '06:30', day: :wednesday },
        'morning_rush'  => { time: '09:30', day: :wednesday },
        'midday'        => { time: '12:30', day: :wednesday },
        'afternoon'     => { time: '15:30', day: :wednesday },
        'evening_rush'  => { time: '18:30', day: :wednesday },
        'night'         => { time: '23:00', day: :wednesday },
        'weekend_day'   => { time: '14:00', day: :saturday },
        'weekend_night' => { time: '22:00', day: :saturday },
      }.freeze

      def band_to_quote_time(band)
        config = BAND_TIMES[band] || BAND_TIMES['morning_rush']
        target_day = config[:day]

        date = Date.today
        # Find the next matching day
        target_wday = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 }[target_day]
        if target_wday
          days_ahead = (target_wday - date.wday) % 7
          days_ahead = 7 if days_ahead == 0 && date.wday != target_wday
          date = date + days_ahead if date.wday != target_wday
        end

        Time.zone.parse("#{date} #{config[:time]}")
      end
    end
  end
end
