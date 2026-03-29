# frozen_string_literal: true

module RoutePricing
  module Admin
    class ProviderHealthController < ApplicationController
      def show
        resolver = RoutePricing::Services::RouteResolver.new
        render json: resolver.provider_health
      end
    end
  end
end
