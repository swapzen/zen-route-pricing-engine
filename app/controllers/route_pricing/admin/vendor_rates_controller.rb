# frozen_string_literal: true

module RoutePricing
  module Admin
    class VendorRatesController < ApplicationController
      # POST /route_pricing/admin/sync_vendor_rates
      def sync
        vendor_code = params[:vendor_code] || 'porter'
        city_code = params[:city_code] || 'hyd'

        loader = VendorConfigLoader.new(vendor_code, city_code)
        result = loader.sync!

        if result[:success]
          render json: { success: true, stats: result[:stats] }, status: :ok
        else
          render json: { success: false, error: result[:error] }, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("SyncVendorRates failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/vendor_rate_cards
      def index
        vendor_code = params[:vendor_code]
        city_code = params[:city_code]

        scope = VendorRateCard.current
        scope = scope.for_vendor(vendor_code) if vendor_code.present?
        scope = scope.for_city(city_code) if city_code.present?

        cards = scope.order(:vendor_code, :city_code, :vehicle_type, :time_band)

        render json: {
          count: cards.count,
          rate_cards: cards.map { |c| serialize_rate_card(c) }
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("ListVendorRateCards failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      # GET /route_pricing/admin/margin_report
      def margin_report
        city_code = params[:city_code] || 'hyd'
        days = (params[:days] || 30).to_i

        quotes = PricingQuote
          .where(city_code: city_code)
          .where.not(vendor_predicted_paise: nil)
          .where('created_at > ?', days.days.ago)

        total = quotes.count
        return render json: { city_code: city_code, days: days, total_quotes: 0 } if total.zero?

        avg_margin_pct = quotes.average(:margin_pct)&.to_f&.round(2)
        avg_margin_paise = quotes.average(:margin_paise)&.to_i

        by_vehicle = quotes.group(:vehicle_type).select(
          'vehicle_type',
          'COUNT(*) as quote_count',
          'AVG(margin_pct) as avg_margin_pct',
          'AVG(margin_paise) as avg_margin_paise'
        ).map do |row|
          {
            vehicle_type: row.vehicle_type,
            quote_count: row[:quote_count],
            avg_margin_pct: row[:avg_margin_pct]&.to_f&.round(2),
            avg_margin_paise: row[:avg_margin_paise]&.to_i
          }
        end

        render json: {
          city_code: city_code,
          days: days,
          total_quotes: total,
          avg_margin_pct: avg_margin_pct,
          avg_margin_paise: avg_margin_paise,
          by_vehicle: by_vehicle
        }, status: :ok
      rescue StandardError => e
        Rails.logger.error("MarginReport failed: #{e.message}")
        render json: { error: e.message }, status: :internal_server_error
      end

      private

      def serialize_rate_card(card)
        {
          id: card.id,
          vendor_code: card.vendor_code,
          city_code: card.city_code,
          vehicle_type: card.vehicle_type,
          time_band: card.time_band,
          base_fare_paise: card.base_fare_paise,
          per_km_rate_paise: card.per_km_rate_paise,
          per_min_rate_paise: card.per_min_rate_paise,
          min_fare_paise: card.min_fare_paise,
          free_km_m: card.free_km_m,
          surge_cap_multiplier: card.surge_cap_multiplier,
          version: card.version,
          effective_from: card.effective_from&.iso8601,
          active: card.active
        }
      end
    end
  end
end
