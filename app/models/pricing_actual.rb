# frozen_string_literal: true

class PricingActual < ApplicationRecord
  # Associations
  belongs_to :pricing_quote

  # Validations
  validates :actual_price_paise, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :vendor, presence: true

  before_create :compute_prediction_variance

  # Calculate variance from quote
  def variance_paise
    actual_price_paise - pricing_quote.price_paise
  end

  def variance_percentage
    return 0 if pricing_quote.price_paise.zero?

    ((variance_paise.to_f / pricing_quote.price_paise) * 100).round(2)
  end

  private

  def compute_prediction_variance
    predicted = pricing_quote&.vendor_predicted_paise
    return unless predicted && predicted > 0

    self.predicted_vendor_paise = predicted
    self.prediction_variance_paise = actual_price_paise - predicted
    self.prediction_variance_pct = ((prediction_variance_paise.to_f / predicted) * 100).round(2)
  end
end
