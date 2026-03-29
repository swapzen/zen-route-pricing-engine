# frozen_string_literal: true

namespace :pricing do
  desc 'Generate drift report for a city'
  task :drift_report, [:city] => :environment do |_t, args|
    city = args[:city] || 'hyderabad'
    puts "Analyzing drift for #{city}..."

    analyzer = RoutePricing::Services::DriftAnalyzer.new(city_code: city)
    report = analyzer.analyze

    puts "\n=== Drift Report: #{city} ==="
    puts "Total decisions: #{report[:total_decisions]}"
    puts "Drifted corridors: #{report[:drifted_count]}"
    puts "Alert level: #{report[:alert_level]}"

    if report[:corridors].any?
      puts "\nTop drifting corridors:"
      report[:corridors].first(10).each do |c|
        puts "  #{c[:vehicle_type]} | #{c[:time_band]} | #{c[:pickup_zone]}→#{c[:drop_zone]} | " \
             "mean: #{c[:mean_variance_pct]}% | samples: #{c[:sample_count]} | " \
             "#{c[:drifted] ? 'DRIFTED' : 'ok'}"
      end
    end

    if report[:recommendations].any?
      puts "\nRecommendations:"
      report[:recommendations].each { |r| puts "  - #{r}" }
    end
  end

  desc 'Check drift thresholds and log warnings'
  task :drift_alert, [:city] => :environment do |_t, args|
    city = args[:city] || 'hyderabad'

    analyzer = RoutePricing::Services::DriftAnalyzer.new(city_code: city)
    report = analyzer.analyze

    case report[:alert_level]
    when 'red'
      Rails.logger.warn("PRICING DRIFT ALERT [RED] city=#{city} drifted=#{report[:drifted_count]} " \
                        "total=#{report[:total_decisions]}")
      puts "RED ALERT: #{report[:drifted_count]} corridors drifting in #{city}"
    when 'yellow'
      Rails.logger.info("PRICING DRIFT WARNING [YELLOW] city=#{city} drifted=#{report[:drifted_count]}")
      puts "WARNING: #{report[:drifted_count]} corridors drifting in #{city}"
    else
      puts "OK: No significant drift in #{city}"
    end
  end
end
