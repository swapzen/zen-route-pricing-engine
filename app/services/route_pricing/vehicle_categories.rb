# frozen_string_literal: true

module RoutePricing
  # Single source of truth for vehicle category groupings.
  # Used for distance band shaping, time-of-day surge, and zone multipliers.
  #
  # Classification rationale:
  #   SMALL: Personal-mobility vehicles (< 100kg capacity)
  #   MID:   Light commercial vehicles (100-1000kg capacity)
  #   HEAVY: Heavy commercial vehicles (1000kg+ capacity)
  module VehicleCategories
    SMALL_VEHICLES = %w[two_wheeler scooter].freeze
    MID_VEHICLES   = %w[mini_3w three_wheeler three_wheeler_ev tata_ace pickup_8ft].freeze
    HEAVY_VEHICLES = %w[eeco tata_407 canter_14ft].freeze

    ALL_VEHICLES = (SMALL_VEHICLES + MID_VEHICLES + HEAVY_VEHICLES).freeze

    def self.category_for(vehicle_type)
      if SMALL_VEHICLES.include?(vehicle_type) then :small
      elsif MID_VEHICLES.include?(vehicle_type) then :mid
      elsif HEAVY_VEHICLES.include?(vehicle_type) then :heavy
      else :mid # safe default for unknown vehicle types
      end
    end

    def self.small?(vehicle_type)
      SMALL_VEHICLES.include?(vehicle_type)
    end

    def self.mid?(vehicle_type)
      MID_VEHICLES.include?(vehicle_type)
    end

    def self.heavy?(vehicle_type)
      HEAVY_VEHICLES.include?(vehicle_type)
    end
  end
end
