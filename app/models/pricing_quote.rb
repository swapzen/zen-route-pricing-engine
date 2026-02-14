# frozen_string_literal: true

class PricingQuote < ApplicationRecord
  # Associations
  has_one :pricing_actual, dependent: :destroy

  # Validations
  validates :city_code, :vehicle_type, :price_paise, presence: true
  validates :price_paise, numericality: { only_integer: true, greater_than: 0 }

  # Format breakdown for API response
  def formatted_breakdown
    breakdown_json.deep_symbolize_keys
  end

  # Convert price to INR (returns float for JSON serialization)
  def price_inr
    (price_paise / 100.0).round(2)
  end

  # Check if quote has expired
  def expired?
    return false unless valid_until

    Time.current > valid_until
  end

  # Seconds remaining before quote expires (0 if expired or no validity set)
  def remaining_seconds
    return 0 unless valid_until

    [(valid_until - Time.current).to_i, 0].max
  end
end
