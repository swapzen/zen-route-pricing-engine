# frozen_string_literal: true

module RoutePricing
  module Admin
    class CompetitorRatesController < ApplicationController
      # GET /route_pricing/admin/competitor_rates
      def index
        city_code = params[:city_code] || 'hyd'
        competitor = params[:competitor] || 'porter'

        file_path = Rails.root.join('config', 'competitors', "#{competitor}_#{city_code}.yml")

        if File.exist?(file_path)
          data = YAML.load_file(file_path)
          render json: { success: true, competitor: data }
        else
          render json: { success: false, error: "No rate card found for #{competitor}/#{city_code}" }
        end
      end

      # GET /route_pricing/admin/competitor_comparison
      def comparison
        city_code = params[:city_code] || 'hyd'
        vehicle_type = params[:vehicle_type]

        # Load competitor rates
        competitor_file = Rails.root.join('config', 'competitors', "porter_#{city_code}.yml")
        competitor_data = File.exist?(competitor_file) ? YAML.load_file(competitor_file) : nil

        # Load our configs
        our_configs = PricingConfig.where(city_code: city_code, active: true)

        comparison = our_configs.map do |config|
          vt = config.vehicle_type
          next if vehicle_type.present? && vt != vehicle_type

          competitor_vehicle = competitor_data&.dig('vehicles', vt) || {}
          competitor_base = (competitor_vehicle['base_fare_rs'] || 0) * 100
          competitor_per_km = (competitor_vehicle['est_per_km_rs'] || 0) * 100

          {
            vehicle_type: vt,
            our_base_fare_paise: config.base_fare_paise,
            competitor_base_fare_paise: competitor_base,
            base_delta_pct: competitor_base > 0 ? (((config.base_fare_paise - competitor_base).to_f / competitor_base) * 100).round(1) : nil,
            our_per_km_paise: config.per_km_rate_paise,
            competitor_per_km_paise: competitor_per_km,
            per_km_delta_pct: competitor_per_km > 0 ? (((config.per_km_rate_paise - competitor_per_km).to_f / competitor_per_km) * 100).round(1) : nil,
            competitor_notes: competitor_vehicle['notes']
          }
        end.compact

        render json: { success: true, city_code: city_code, comparisons: comparison }
      end
    end
  end
end
