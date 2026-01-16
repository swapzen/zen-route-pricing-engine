# frozen_string_literal: true

# PricingDistanceSlab represents tiered per-km rates for different distance brackets.
# Example: 0-3km = ₹12/km, 3-10km = ₹8/km, 10-25km = ₹6/km, 25+ km = ₹5/km
#
# This enables telescopic pricing where short trips have higher per-km rates
# (covering driver time, loading, etc.) and long trips have lower rates
# (highway efficiency, economies of scale).
class PricingDistanceSlab < ApplicationRecord
  belongs_to :pricing_config

  # Validations
  validates :min_distance_m, presence: true, 
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :per_km_rate_paise, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :pricing_config_id, uniqueness: { scope: :min_distance_m,
            message: 'already has a slab for this distance' }

  # Scopes
  scope :ordered, -> { order(min_distance_m: :asc) }

  # Get the rate for a specific distance in meters
  def self.rate_for_distance(distance_m)
    ordered.where('min_distance_m <= ?', distance_m)
           .where('max_distance_m IS NULL OR max_distance_m > ?', distance_m)
           .last
  end

  # Calculate total cost for a given distance using all slabs
  def self.calculate_slab_cost(slabs, distance_m)
    return 0 if slabs.empty? || distance_m <= 0

    distance_km = distance_m / 1000.0
    total_paise = 0
    remaining_km = distance_km

    slabs.ordered.each do |slab|
      slab_start_km = slab.min_distance_m / 1000.0
      slab_end_km = slab.max_distance_m ? (slab.max_distance_m / 1000.0) : Float::INFINITY

      # Skip if we haven't reached this slab yet
      next if remaining_km <= 0

      # Calculate km in this slab
      km_before_slab = [slab_start_km, distance_km - remaining_km].max
      km_in_slab = [[slab_end_km, distance_km].min - km_before_slab, 0].max
      km_in_slab = [km_in_slab, remaining_km].min

      # Add cost for this slab
      total_paise += (km_in_slab * slab.per_km_rate_paise).round
      remaining_km -= km_in_slab
    end

    total_paise
  end
end
