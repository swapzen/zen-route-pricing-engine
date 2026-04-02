# frozen_string_literal: true

namespace :pricing do
  desc "Run drift analysis and log alerts (for cron scheduling)"
  task drift_check: :environment do
    city_code = ENV['CITY_CODE'] || 'hyd'
    hours = (ENV['HOURS'] || 24).to_i

    puts "Running drift check for #{city_code} (last #{hours}h)..."

    # DriftAnalyzer uses lookback_days, so convert hours to days (minimum 1 day)
    lookback_days = [hours / 24.0, 1].max.ceil

    analyzer = RoutePricing::Services::DriftAnalyzer.new(city_code: city_code, lookback_days: lookback_days)
    report = analyzer.analyze

    if report && report[:total_decisions] > 0
      drifted = report[:drifted_count] || 0
      total = report[:total_decisions] || 0
      pct = total > 0 ? (drifted.to_f / total * 100).round(1) : 0

      puts "Drift report: #{drifted}/#{total} quotes drifted (#{pct}%)"
      puts "Alert level: #{report[:alert_level] || 'unknown'}"

      if pct > 20
        Rails.logger.error("[DRIFT_ALERT] HIGH: #{pct}% drift rate for #{city_code}")
      elsif pct > 10
        Rails.logger.warn("[DRIFT_ALERT] MEDIUM: #{pct}% drift rate for #{city_code}")
      else
        Rails.logger.info("[DRIFT_CHECK] OK: #{pct}% drift rate for #{city_code}")
      end
    else
      puts "No drift data available"
    end
  end
end
