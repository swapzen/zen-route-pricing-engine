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
end
