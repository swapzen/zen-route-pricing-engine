# frozen_string_literal: true

class PricingModelConfig < ApplicationRecord
  MODES = %w[shadow canary active].freeze

  validates :algorithm_name, :model_version, :mode, presence: true
  validates :mode, inclusion: { in: MODES }
  validates :algorithm_name, uniqueness: { scope: :city_code }
  validates :canary_pct, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :active_models, -> { where(active: true) }
  scope :for_city, ->(city_code) { where(city_code: [city_code, nil]) }
  scope :shadow, -> { where(mode: 'shadow') }
  scope :canary, -> { where(mode: 'canary') }

  def self.active_model(city_code)
    active_models
      .for_city(city_code)
      .order(Arel.sql("CASE WHEN city_code IS NOT NULL THEN 0 ELSE 1 END"), created_at: :desc)
      .first
  end
end
