module RoutePricing
  module Services
    class PricingLogger
      def self.log(level, event, **data)
        payload = {
          event: event,
          request_id: Thread.current[:request_id],
          timestamp: Time.current.iso8601,
          **data
        }.compact

        Rails.logger.send(level, "[PRICING] #{payload.to_json}")
      end

      def self.info(event, **data) = log(:info, event, **data)
      def self.warn(event, **data) = log(:warn, event, **data)
      def self.error(event, **data) = log(:error, event, **data)
    end
  end
end
