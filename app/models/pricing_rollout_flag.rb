# frozen_string_literal: true

class PricingRolloutFlag < ApplicationRecord
  validates :flag_name, presence: true
  validates :flag_name, uniqueness: { scope: :city_code }
  validates :rollout_pct, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :for_flag, ->(name) { where(flag_name: name) }
  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :global, -> { where(city_code: nil) }

  def self.enabled?(flag_name, city_code: nil)
    cache_key = "rollout_flag:#{flag_name}:#{city_code}"
    Rails.cache.fetch(cache_key, expires_in: 60.seconds) do
      # Check city-specific flag first, then global
      flag = find_by(flag_name: flag_name, city_code: city_code) ||
             find_by(flag_name: flag_name, city_code: nil)

      next false unless flag&.enabled

      # If rollout_pct < 100, probabilistic check
      next true if flag.rollout_pct >= 100

      rand(100) < flag.rollout_pct
    end
  end

  def self.set!(flag_name, enabled:, city_code: nil, rollout_pct: 100)
    flag = find_or_initialize_by(flag_name: flag_name, city_code: city_code)
    flag.update!(enabled: enabled, rollout_pct: rollout_pct)
    Rails.cache.delete("rollout_flag:#{flag_name}:#{city_code}")
    flag
  end
end
