# frozen_string_literal: true

class PricingSnapshot < ApplicationRecord
  validates :city_code, presence: true
  validates :name, presence: true

  scope :for_city, ->(code) { where('LOWER(city_code) = LOWER(?)', code) }
  scope :recent, -> { order(created_at: :desc) }
end
