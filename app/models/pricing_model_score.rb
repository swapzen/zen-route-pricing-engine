# frozen_string_literal: true

class PricingModelScore < ApplicationRecord
  belongs_to :pricing_quote, optional: true

  validates :model_version, :city_code, presence: true

  scope :for_model, ->(version) { where(model_version: version) }
  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :shadow_mode, -> { joins("INNER JOIN pricing_model_configs ON pricing_model_configs.model_version = pricing_model_scores.model_version AND pricing_model_configs.mode = 'shadow'") }
  scope :with_outcomes, -> { where.not(outcome: nil) }
  scope :recent, ->(n = 100) { order(created_at: :desc).limit(n) }

  def self.log_shadow_score!(quote_id, model_version, deterministic, suggested, features)
    quote = PricingQuote.find(quote_id)
    create!(
      pricing_quote_id: quote_id,
      model_version: model_version,
      city_code: quote.city_code,
      vehicle_type: quote.vehicle_type,
      deterministic_price_paise: deterministic,
      model_suggested_paise: suggested,
      features: features
    )
  end
end
