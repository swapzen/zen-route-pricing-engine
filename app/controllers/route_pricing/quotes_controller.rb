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
        request_id: params[:request_id],
        weight_kg: params[:weight_kg]&.to_f,
        quote_time: params[:quote_time].present? ? Time.zone.parse(params[:quote_time]) : Time.current
      )

      if result[:error]
        status = case result[:code].to_i
                 when 400 then :bad_request
                 when 401 then :unauthorized
                 when 404 then :not_found
                 when 422 then :unprocessable_entity
                 else
                   result[:code].to_i >= 500 ? :internal_server_error : :unprocessable_entity
                 end
        render json: { error: result[:error], code: result[:code] }, status: status
      else
        render json: result, status: :ok
      end
    rescue ArgumentError => e
      render json: { error: "Invalid coordinates: #{e.message}" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("CreateQuote failed: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to create quote" }, status: :internal_server_error
    end

    # POST /route_pricing/round_trip_quote
    def round_trip_quote
      pickup_lat = BigDecimal(params[:pickup_lat].to_s)
      pickup_lng = BigDecimal(params[:pickup_lng].to_s)
      drop_lat = BigDecimal(params[:drop_lat].to_s)
      drop_lng = BigDecimal(params[:drop_lng].to_s)

      quote_time = params[:quote_time].present? ? Time.zone.parse(params[:quote_time]) : Time.current
      return_quote_time = params[:return_quote_time].present? ? Time.zone.parse(params[:return_quote_time]) : nil

      engine = RoutePricing::Services::QuoteEngine.new
      result = engine.create_round_trip_quote(
        city_code: params[:city_code],
        vehicle_type: params[:vehicle_type],
        pickup_lat: pickup_lat,
        pickup_lng: pickup_lng,
        drop_lat: drop_lat,
        drop_lng: drop_lng,
        item_value_paise: params[:item_value_paise]&.to_i,
        request_id: params[:request_id],
        quote_time: quote_time,
        return_quote_time: return_quote_time,
        weight_kg: params[:weight_kg]&.to_f
      )

      if result[:error]
        render json: { error: result[:error], code: result[:code] }, status: :internal_server_error
      else
        render json: result, status: :ok
      end
    rescue ArgumentError => e
      render json: { error: "Invalid parameters: #{e.message}" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("RoundTripQuote failed: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to create round-trip quote" }, status: :internal_server_error
    end

    # POST /route_pricing/multi_quote
    def multi_quote
      pickup_lat = BigDecimal(params[:pickup_lat].to_s)
      pickup_lng = BigDecimal(params[:pickup_lng].to_s)
      drop_lat = BigDecimal(params[:drop_lat].to_s)
      drop_lng = BigDecimal(params[:drop_lng].to_s)

      engine = RoutePricing::Services::QuoteEngine.new
      result = engine.create_multi_quote(
        city_code: params[:city_code],
        pickup_lat: pickup_lat,
        pickup_lng: pickup_lng,
        drop_lat: drop_lat,
        drop_lng: drop_lng,
        item_value_paise: params[:item_value_paise]&.to_i,
        request_id: params[:request_id],
        weight_kg: params[:weight_kg]&.to_f
      )

      if result[:error]
        render json: { error: result[:error], code: result[:code] }, status: :internal_server_error
      else
        render json: result, status: :ok
      end
    rescue ArgumentError => e
      render json: { error: "Invalid coordinates: #{e.message}" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("MultiQuote failed: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to create multi-quote" }, status: :internal_server_error
    end

    # POST /route_pricing/validate_quote
    def validate_quote
      quote = PricingQuote.find_by(id: params[:quote_id])

      unless quote
        return render json: { error: "Quote not found" }, status: :not_found
      end

      render json: {
        quote_id: quote.id,
        valid: !quote.expired?,
        expired: quote.expired?,
        price_paise: quote.price_paise,
        price_inr: quote.price_inr,
        valid_until: quote.valid_until&.iso8601,
        remaining_seconds: quote.remaining_seconds,
        vehicle_type: quote.vehicle_type,
        created_at: quote.created_at.iso8601
      }, status: :ok
    rescue StandardError => e
      Rails.logger.error("ValidateQuote failed: #{e.message}")
      render json: { error: "Failed to validate quote" }, status: :internal_server_error
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
