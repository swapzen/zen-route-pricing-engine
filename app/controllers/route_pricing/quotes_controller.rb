# frozen_string_literal: true

module RoutePricing
  class QuotesController < ApplicationController
    # POST /route_pricing/create_quote
    def create
      # Parse coordinates to BigDecimal
      pickup_lat = BigDecimal(params[:pickup_lat].to_s)
      pickup_lng = BigDecimal(params[:pickup_lng].to_s)
      drop_lat = BigDecimal(params[:drop_lat].to_s)
      drop_lng = BigDecimal(params[:drop_lng].to_s)

      # Call quote engine
      engine = RoutePricing::Services::QuoteEngine.new
      result = engine.create_quote(
        city_code: params[:city_code],
        vehicle_type: params[:vehicle_type],
        pickup_lat: pickup_lat,
        pickup_lng: pickup_lng,
        drop_lat: drop_lat,
        drop_lng: drop_lng,
        item_value_paise: params[:item_value_paise]&.to_i,
        request_id: params[:request_id]
      )

      if result[:error]
        render json: { error: result[:error] }, status: :unprocessable_entity
      else
        render json: result, status: :ok
      end
    rescue ArgumentError => e
      render json: { error: "Invalid coordinates: #{e.message}" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("CreateQuote failed: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to create quote" }, status: :internal_server_error
    end

    # POST /route_pricing/record_actual
    def record_actual
      quote = PricingQuote.find_by(id: params[:pricing_quote_id])
      
      unless quote
        return render json: { error: "Quote not found" }, status: :not_found
      end

      actual = PricingActual.create!(
        pricing_quote: quote,
        vendor: params[:vendor] || 'porter',
        vendor_booking_ref: params[:vendor_booking_ref],
        actual_price_paise: params[:actual_price_paise].to_i,
        notes: params[:notes]
      )

      render json: {
        success: true,
        actual_id: actual.id,
        variance_paise: actual.variance_paise,
        variance_percentage: actual.variance_percentage
      }, status: :created
    rescue StandardError => e
      Rails.logger.error("RecordActual failed: #{e.message}")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
