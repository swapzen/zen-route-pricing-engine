# frozen_string_literal: true

class PricingOutcome < ApplicationRecord
  OUTCOMES = %w[accepted rejected expired cancelled].freeze

  belongs_to :pricing_quote

  validates :outcome, :city_code, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }

  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :for_zone, ->(zone_code) { where(pickup_zone_code: zone_code).or(where(drop_zone_code: zone_code)) }
  scope :for_hex, ->(h3_index) { where(h3_index_r7: h3_index) }
  scope :accepted, -> { where(outcome: 'accepted') }
  scope :rejected, -> { where(outcome: 'rejected') }
  scope :recent, ->(hours = 24) { where('created_at >= ?', hours.hours.ago) }

  def self.acceptance_rate(scope = all)
    total = scope.count
    return 0.0 if total.zero?

    (scope.accepted.count.to_f / total * 100).round(2)
  end

  def self.rejection_rate(scope = all)
    total = scope.count
    return 0.0 if total.zero?

    (scope.rejected.count.to_f / total * 100).round(2)
  end
end
