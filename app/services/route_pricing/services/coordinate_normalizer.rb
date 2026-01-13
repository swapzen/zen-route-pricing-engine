# frozen_string_literal: true

module RoutePricing
  module Services
    class CoordinateNormalizer
      class InvalidCoordinateError < StandardError; end

      def self.normalize(lat, lng, precision: 4)
        new.normalize(lat, lng, precision: precision)
      end

      def normalize(lat, lng, precision: 4)
        lat_f = Float(lat)
        lng_f = Float(lng)

        # Validate ranges
        unless lat_f.between?(-90, 90)
          raise InvalidCoordinateError, "Latitude must be between -90 and 90, got #{lat_f}"
        end

        unless lng_f.between?(-180, 180)
          raise InvalidCoordinateError, "Longitude must be between -180 and 180, got #{lng_f}"
        end

        # Round to specified precision
        {
          lat: lat_f.round(precision),
          lng: lng_f.round(precision)
        }
      rescue ArgumentError => e
        raise InvalidCoordinateError, "Invalid coordinate format: #{e.message}"
      end
    end
  end
end
