# frozen_string_literal: true

class PricingEmergencyFreeze < ApplicationRecord
  validates :reason, :activated_by, :activated_at, presence: true

  scope :active_for_city, ->(city_code) { where(city_code: city_code, active: true) }
  scope :global_active, -> { where(city_code: nil, active: true) }

  def self.city_frozen?(city_code)
    global_active.exists? || active_for_city(city_code).exists?
  end

  def deactivate!(actor)
    update!(
      active: false,
      deactivated_by: actor,
      deactivated_at: Time.current
    )
  end
end
