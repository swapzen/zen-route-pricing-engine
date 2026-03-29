# frozen_string_literal: true

class PricingChangeLog < ApplicationRecord
  validates :entity_type, :entity_id, :action, :actor, presence: true

  scope :for_entity, ->(type, id) { where(entity_type: type, entity_id: id) }
  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :by_actor, ->(actor) { where(actor: actor) }
  scope :recent, ->(n = 50) { order(created_at: :desc).limit(n) }

  def self.log!(entity, action, actor, before: {}, after: {})
    diff = compute_diff(before, after)

    create!(
      entity_type: entity.class.name,
      entity_id: entity.id,
      action: action,
      actor: actor,
      before_state: before,
      after_state: after,
      diff: diff,
      city_code: entity.try(:city_code)
    )
  end

  def self.compute_diff(before, after)
    return {} if before.blank? && after.blank?

    changed_keys = (before.keys | after.keys).select do |key|
      before[key] != after[key]
    end

    changed_keys.each_with_object({}) do |key, memo|
      memo[key] = { from: before[key], to: after[key] }
    end
  end
end
