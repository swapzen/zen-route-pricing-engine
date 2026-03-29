# frozen_string_literal: true

class InterZoneConfig < ApplicationRecord
  validates :city_code, presence: true
  validates :origin_weight, :destination_weight, numericality: { greater_than: 0, less_than_or_equal_to: 1 }

  scope :active, -> { where(active: true) }

  def self.load_for_city(city_code)
    record = active.find_by(city_code: city_code.to_s.downcase)
    return nil unless record

    # Build lookup hash matching the format zone_pricing_resolver expects
    adjustments = {}
    (record.type_adjustments || {}).each do |pattern_key, time_values|
      next if pattern_key == 'default'
      symbolized = time_values.transform_keys(&:to_sym).transform_values(&:to_f)

      parts = pattern_key.split('_to_')
      next unless parts.length == 2

      from_part = parts[0]
      to_part = parts[1]

      if from_part == 'any'
        adjustments[[:any, to_part]] = symbolized
      elsif to_part == 'any'
        adjustments[[from_part, :any]] = symbolized
      else
        adjustments[[from_part, to_part]] = symbolized
      end
    end

    default_adj = (record.type_adjustments&.dig('default') || {}).transform_keys(&:to_sym).transform_values(&:to_f)

    {
      origin_weight: record.origin_weight,
      destination_weight: record.destination_weight,
      adjustments: adjustments,
      default: default_adj
    }
  end
end
