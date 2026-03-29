# frozen_string_literal: true

module RoutePricing
  module Services
    class DemandTracker
      BUCKET_TTL = 15.minutes
      DEMAND_THRESHOLD = 5  # quotes in 15min to trigger demand signal
      SURGE_WRITE_INTERVAL = 5.minutes

      def initialize(city_code:)
        @city_code = city_code.to_s.downcase
      end

      # Record a quote event for a pickup H3 R7 cell (fire-and-forget)
      def record_quote(h3_r7:, vehicle_type: nil)
        return unless h3_r7.present?

        bucket = time_bucket
        key = "demand:#{@city_code}:#{h3_r7}:#{bucket}"

        count = Rails.cache.increment(key, 1, expires_in: BUCKET_TTL) || 1

        # If demand crosses threshold, write to h3_surge_buckets for H3SurgeResolver
        if count == DEMAND_THRESHOLD
          write_demand_surge(h3_r7, bucket)
        end
      rescue StandardError => e
        Rails.logger.debug("DemandTracker record_quote error: #{e.message}")
      end

      # Record an acceptance event (reduces demand pressure)
      def record_accept(h3_r7:)
        return unless h3_r7.present?

        bucket = time_bucket
        accept_key = "demand_accept:#{@city_code}:#{h3_r7}:#{bucket}"
        Rails.cache.increment(accept_key, 1, expires_in: BUCKET_TTL)
      rescue StandardError => e
        Rails.logger.debug("DemandTracker record_accept error: #{e.message}")
      end

      # Record a rejection/expiry event (increases demand pressure)
      def record_reject(h3_r7:)
        return unless h3_r7.present?

        bucket = time_bucket
        reject_key = "demand_reject:#{@city_code}:#{h3_r7}:#{bucket}"
        Rails.cache.increment(reject_key, 1, expires_in: BUCKET_TTL)
      rescue StandardError => e
        Rails.logger.debug("DemandTracker record_reject error: #{e.message}")
      end

      # Get current demand score for a cell (0.0-1.0)
      def demand_score(h3_r7:)
        return 0.0 unless h3_r7.present?

        bucket = time_bucket
        key = "demand:#{@city_code}:#{h3_r7}:#{bucket}"
        count = Rails.cache.read(key).to_i

        # Normalize: 0 quotes = 0.0, DEMAND_THRESHOLD+ = 1.0
        [count.to_f / DEMAND_THRESHOLD, 1.0].min
      rescue StandardError
        0.0
      end

      private

      # 15-minute time bucket
      def time_bucket
        (Time.current.to_i / 900)
      end

      # Write demand surge signal to h3_surge_buckets table
      # This is picked up by H3SurgeResolver
      def write_demand_surge(h3_r7, bucket)
        return unless defined?(H3SurgeBucket) && H3SurgeBucket.table_exists?

        # Deduplicate: only write once per cell per bucket
        write_key = "demand_written:#{@city_code}:#{h3_r7}:#{bucket}"
        return if Rails.cache.read(write_key)

        H3SurgeBucket.upsert(
          {
            city_code: @city_code,
            h3_index_r7: h3_r7,
            surge_multiplier: 1.1, # Mild demand-driven surge
            reason: 'demand_signal',
            expires_at: Time.current + BUCKET_TTL,
            created_at: Time.current,
            updated_at: Time.current
          },
          unique_by: [:city_code, :h3_index_r7]
        )

        Rails.cache.write(write_key, true, expires_in: SURGE_WRITE_INTERVAL)
      rescue StandardError => e
        Rails.logger.debug("DemandTracker write_demand_surge error: #{e.message}")
      end
    end
  end
end
