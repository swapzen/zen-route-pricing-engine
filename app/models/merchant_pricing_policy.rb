# frozen_string_literal: true

class MerchantPricingPolicy < ApplicationRecord
  POLICY_TYPES = %w[floor cap discount_pct markup_pct fixed_rate].freeze

  validates :merchant_id, :policy_type, presence: true
  validates :policy_type, inclusion: { in: POLICY_TYPES }
  validates :value_paise, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :value_pct, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :priority, numericality: { only_integer: true }

  scope :active_for_merchant, ->(merchant_id) { where(merchant_id: merchant_id, active: true) }
  scope :for_city, ->(city_code) { where(city_code: [city_code, nil]) }
  scope :for_vehicle, ->(vehicle_type) { where(vehicle_type: [vehicle_type, nil]) }
  scope :effective_on, ->(date) {
    where('effective_from IS NULL OR effective_from <= ?', date)
      .where('effective_until IS NULL OR effective_until >= ?', date)
  }

  # Apply all matching merchant policies to a base price.
  # Order: fixed_rate (overrides) → markup → discount → cap → floor
  def self.apply_policies(merchant_id, base_price_paise, city: nil, vehicle: nil)
    policies = active_for_merchant(merchant_id)
                 .for_city(city)
                 .for_vehicle(vehicle)
                 .effective_on(Date.current)
                 .order(priority: :desc)

    return { final_price_paise: base_price_paise, adjustments: [] } if policies.empty?

    price = base_price_paise
    adjustments = []

    # Group by type and apply in deterministic order
    by_type = policies.group_by(&:policy_type)

    # 1. Fixed rate overrides everything
    if by_type['fixed_rate']&.any?
      policy = by_type['fixed_rate'].first
      old_price = price
      price = policy.value_paise
      adjustments << { policy_type: 'fixed_rate', policy_id: policy.id, delta: price - old_price }
      return { final_price_paise: price, adjustments: adjustments }
    end

    # 2. Markup
    by_type['markup_pct']&.each do |policy|
      delta = (price * policy.value_pct / 100.0).round
      price += delta
      adjustments << { policy_type: 'markup_pct', policy_id: policy.id, delta: delta }
    end

    # 3. Discount
    by_type['discount_pct']&.each do |policy|
      delta = (price * policy.value_pct / 100.0).round
      price -= delta
      adjustments << { policy_type: 'discount_pct', policy_id: policy.id, delta: -delta }
    end

    # 4. Cap (upper limit)
    by_type['cap']&.each do |policy|
      if price > policy.value_paise
        delta = policy.value_paise - price
        price = policy.value_paise
        adjustments << { policy_type: 'cap', policy_id: policy.id, delta: delta }
      end
    end

    # 5. Floor (lower limit)
    by_type['floor']&.each do |policy|
      if price < policy.value_paise
        delta = policy.value_paise - price
        price = policy.value_paise
        adjustments << { policy_type: 'floor', policy_id: policy.id, delta: delta }
      end
    end

    { final_price_paise: price, adjustments: adjustments }
  end
end
