# frozen_string_literal: true

class PricingActual < ApplicationRecord
  # Associations
  belongs_to :pricing_quote

  # Validations
  validates :actual_price_paise, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :vendor, presence: true

  # Calculate variance from quote
  def variance_paise
    actual_price_paise - pricing_quote.price_paise
  end

  def variance_percentage
    return 0 if pricing_quote.price_paise.zero?
    
    ((variance_paise.to_f / pricing_quote.price_paise) * 100).round(2)
  end
end
