# frozen_string_literal: true

module RoutePricing
  module Services
    class BackhaulCalculator
      # Default return probabilities by zone_type
      # Lower probability = higher chance of empty return = higher premium
      DEFAULT_PROBABILITIES = {
        'tech_corridor'          => 0.85,
        'business_cbd'           => 0.75,
        'airport_logistics'      => 0.15,
        'industrial'             => 0.25,
        'residential_dense'      => 0.60,
        'residential_mixed'      => 0.55,
        'residential_growth'     => 0.45,
        'premium_residential'    => 0.50,
        'traditional_commercial' => 0.70,
        'heritage_commercial'    => 0.65,
        'outer_ring'             => 0.30,
        'default'                => 0.50
      }.freeze

      # Calculate backhaul multiplier for a trip's drop zone
      # @param zone [Hash] zone_info from ZonePricingResolver (:drop_zone, :drop_type)
      # @param time_band [String] current time band
      # @param city_code [String] city code
      # @param max_premium [Float] max backhaul premium (default 0.20 = 20%)
      # @return [Float] multiplier (1.0 = no change, up to 1 + max_premium)
      def calculate(zone:, time_band:, city_code:, max_premium: 0.20)
        drop_zone_code = zone&.dig(:drop_zone)
        drop_zone_type = zone&.dig(:drop_type) || 'default'

        # Try DB record first
        return_probability = lookup_db_probability(drop_zone_code, city_code, time_band)

        # Fall back to zone_type default
        return_probability ||= DEFAULT_PROBABILITIES[drop_zone_type] || DEFAULT_PROBABILITIES['default']

        # Formula: backhaul_mult = 1.0 + (1.0 - return_probability) * max_premium
        # airport (0.15 prob) → 1.0 + 0.85 * 0.20 = 1.17x
        # tech (0.85 prob) → 1.0 + 0.15 * 0.20 = 1.03x
        1.0 + (1.0 - return_probability) * max_premium
      rescue StandardError => e
        Rails.logger.warn("BackhaulCalculator error: #{e.message}")
        1.0
      end

      private

      def lookup_db_probability(drop_zone_code, city_code, time_band)
        return nil unless drop_zone_code
        return nil unless defined?(BackhaulProbability) && BackhaulProbability.table_exists?

        zone = Zone.find_by(zone_code: drop_zone_code, city: city_code)
        return nil unless zone

        record = BackhaulProbability.find_by(zone_id: zone.id, time_band: time_band)
        record ||= BackhaulProbability.find_by(zone_id: zone.id, time_band: 'all')
        record&.return_probability
      rescue StandardError
        nil
      end
    end
  end
end
