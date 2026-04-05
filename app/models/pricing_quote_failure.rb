# frozen_string_literal: true

# PricingQuoteFailure logs every quote request that failed so admins can spot
# coverage gaps (zones/cells without pricing, route resolution issues, etc).
class PricingQuoteFailure < ApplicationRecord
  FAILURE_CODES = %w[zone_not_found no_config route_failed validation other].freeze

  validates :city_code, :failure_code, presence: true

  scope :for_city, ->(city_code) { where(city_code: city_code.to_s.downcase) }
  scope :recent, ->(hours = 24) { where('created_at >= ?', hours.hours.ago) }
  scope :by_code, ->(code) { where(failure_code: code) }
end
