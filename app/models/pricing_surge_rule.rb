# frozen_string_literal: true

class PricingSurgeRule < ApplicationRecord
  # Associations
  belongs_to :pricing_config
  belongs_to :created_by, class_name: 'User', foreign_key: 'created_by_id', optional: true

  # Constants
  RULE_TYPES = %w[time_of_day day_of_week traffic_level event_type].freeze

  # Validations
  validates :rule_type, presence: true, inclusion: { in: RULE_TYPES }
  validates :multiplier, numericality: { greater_than: 0 }
  validates :condition_json, presence: true
  validate :validate_condition_structure

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_time, ->(time) {
    where(active: true).select do |rule|
      rule.time_applicable?(time)
    end
  }

  # Check if this rule applies to given conditions
  def applicable?(time:, traffic_ratio: nil)
    return false unless active

    case rule_type
    when 'time_of_day'
      time_of_day_applicable?(time)
    when 'day_of_week'
      day_of_week_applicable?(time)
    when 'traffic_level'
      traffic_ratio.present? && traffic_level_applicable?(traffic_ratio)
    when 'event_type'
      event_type_applicable?(time)
    else
      false
    end
  end

  # Evaluate rule - returns multiplier if applicable, else 1.0
  def evaluate(time:, traffic_ratio: nil)
    applicable?(time: time, traffic_ratio: traffic_ratio) ? multiplier : 1.0
  end

  private

  def time_of_day_applicable?(time)
    start_hour = condition_json['start_hour']
    end_hour = condition_json['end_hour']
    days = condition_json['days'] || []

    return false if start_hour.nil? || end_hour.nil?

    hour_match = time.hour >= start_hour && time.hour < end_hour
    day_match = days.empty? || days.include?(time.strftime('%a'))

    hour_match && day_match
  end

  def day_of_week_applicable?(time)
    days = condition_json['days'] || []
    days.include?(time.strftime('%a'))
  end

  def traffic_level_applicable?(traffic_ratio)
    min_ratio = condition_json['min_duration_ratio']
    return false if min_ratio.nil?

    traffic_ratio >= min_ratio
  end

  def event_type_applicable?(time)
    start_date = condition_json['start_date']
    end_date = condition_json['end_date']

    return false if start_date.nil? || end_date.nil?

    time.to_date.between?(Date.parse(start_date), Date.parse(end_date))
  rescue ArgumentError
    false
  end

  def validate_condition_structure
    case rule_type
    when 'time_of_day'
      errors.add(:condition_json, 'must have start_hour and end_hour') unless
        condition_json['start_hour'] && condition_json['end_hour']
    when 'traffic_level'
      errors.add(:condition_json, 'must have min_duration_ratio') unless
        condition_json['min_duration_ratio']
    when 'event_type'
      errors.add(:condition_json, 'must have start_date and end_date') unless
        condition_json['start_date'] && condition_json['end_date']
    end
  end
end
