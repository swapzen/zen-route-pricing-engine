# frozen_string_literal: true

module RoutePricing
  module Services
    # Circuit breaker for external API calls (Google Maps, Weather, etc.)
    # States: closed → open → half_open → closed
    #
    # Usage:
    #   breaker = CircuitBreaker.new(service: 'google_maps', threshold: 3, timeout: 120)
    #   result = breaker.call { provider.get_route(...) }
    #
    class CircuitBreaker
      class CircuitOpenError < StandardError; end

      STATES = %i[closed open half_open].freeze

      def initialize(service:, threshold: 3, timeout: 120, window: 300)
        @service = service
        @threshold = threshold       # failures before opening
        @timeout = timeout           # seconds to stay open before half_open
        @window = window             # failure counting window (seconds)
        @state_key = "circuit:#{service}:state"
        @failures_key = "circuit:#{service}:failures"
        @opened_at_key = "circuit:#{service}:opened_at"
        @success_key = "circuit:#{service}:successes"
        @fallback_key = "circuit:#{service}:fallbacks"
      end

      def call(&block)
        case state
        when :open
          if Time.current.to_i - opened_at >= @timeout
            transition_to(:half_open)
            try_call(&block)
          else
            record_fallback
            raise CircuitOpenError, "Circuit open for #{@service}"
          end
        when :half_open
          try_call(&block)
        when :closed
          try_call(&block)
        end
      end

      def state
        (cache_read(@state_key) || 'closed').to_sym
      end

      def stats
        {
          service: @service,
          state: state,
          failures: (cache_read(@failures_key) || 0).to_i,
          successes: (cache_read(@success_key) || 0).to_i,
          fallbacks: (cache_read(@fallback_key) || 0).to_i,
          threshold: @threshold
        }
      end

      private

      def try_call
        result = yield
        record_success
        result
      rescue StandardError => e
        record_failure
        raise
      end

      def record_success
        cache_increment(@success_key, @window)
        if state == :half_open
          transition_to(:closed)
          cache_write(@failures_key, 0, @window)
        end
      end

      def record_failure
        count = cache_increment(@failures_key, @window)
        if count >= @threshold
          transition_to(:open)
          cache_write(@opened_at_key, Time.current.to_i, @timeout + 60)
        end
      end

      def record_fallback
        cache_increment(@fallback_key, @window)
      end

      def opened_at
        (cache_read(@opened_at_key) || 0).to_i
      end

      def transition_to(new_state)
        cache_write(@state_key, new_state.to_s, @timeout + 60)
        Rails.logger.info("[CIRCUIT_BREAKER] #{@service}: #{state} → #{new_state}")
      end

      # Cache helpers — use Rails.cache (Redis or memory)
      def cache_read(key)
        Rails.cache.read(key)
      end

      def cache_write(key, value, ttl)
        Rails.cache.write(key, value, expires_in: ttl.seconds)
      end

      def cache_increment(key, ttl)
        current = (cache_read(key) || 0).to_i + 1
        cache_write(key, current, ttl)
        current
      end
    end
  end
end
