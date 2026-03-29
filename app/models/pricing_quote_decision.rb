# frozen_string_literal: true

class PricingQuoteDecision < ApplicationRecord
  DRIFT_THRESHOLD_PCT = 15.0

  belongs_to :pricing_quote

  validates :city_code, :vehicle_type, :quoted_price_paise, :actual_price_paise, presence: true

  scope :for_city, ->(city_code) { where(city_code: city_code) }
  scope :for_vehicle, ->(vehicle_type) { where(vehicle_type: vehicle_type) }
  scope :for_time_band, ->(time_band) { where(time_band: time_band) }
  scope :drifted, -> { where(within_threshold: false) }
  scope :recent, ->(days = 7) { where('created_at >= ?', days.days.ago) }

  def self.log_decision!(quote, actual)
    variance = actual.actual_price_paise - quote.price_paise
    variance_pct = quote.price_paise > 0 ? ((variance.to_f / quote.price_paise) * 100).round(2) : 0

    breakdown = quote.breakdown_json || {}
    zone_info = breakdown['zone_info'] || breakdown[:zone_info] || {}

    create!(
      pricing_quote_id: quote.id,
      city_code: quote.city_code,
      vehicle_type: quote.vehicle_type,
      time_band: zone_info['time_band'] || zone_info[:time_band],
      pickup_zone_code: zone_info['pickup_zone'] || zone_info[:pickup_zone],
      drop_zone_code: zone_info['drop_zone'] || zone_info[:drop_zone],
      quoted_price_paise: quote.price_paise,
      actual_price_paise: actual.actual_price_paise,
      variance_paise: variance,
      variance_pct: variance_pct,
      pricing_tier: zone_info['pricing_tier'] || zone_info[:pricing_tier],
      distance_km: quote.distance_m ? (quote.distance_m / 1000.0).round(2) : nil,
      config_version: quote.pricing_version,
      within_threshold: variance_pct.abs <= DRIFT_THRESHOLD_PCT
    )
  end
end
