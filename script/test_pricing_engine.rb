#!/usr/bin/env ruby
# =====================================================================
# SwapZen Pricing Engine - Comprehensive Test Suite
# =====================================================================
# Tests all routes, time bands, and vehicle types against Porter benchmarks
# 
# Usage:
#   bundle exec rails runner script/test_pricing_engine.rb
#   ROUTE_PROVIDER_STRATEGY=google bundle exec rails runner script/test_pricing_engine.rb
#   bundle exec rails runner script/test_pricing_engine.rb --quick  # Only show failures
# =====================================================================

require_relative '../config/environment'

# Parse command line arguments
QUICK_MODE = ARGV.include?('--quick') || ARGV.include?('-q')
SHOW_DETAILS = !QUICK_MODE

# =====================================================================
# Configuration
# =====================================================================
Time.zone = 'Asia/Kolkata'

TIMES = {
  morning:   Time.zone.parse('2026-01-15 09:00'),
  afternoon: Time.zone.parse('2026-01-15 15:00'),
  evening:   Time.zone.parse('2026-01-15 18:00')
}

VEHICLES = %w[two_wheeler scooter mini_3w three_wheeler tata_ace pickup_8ft canter_14ft]

# Variance thresholds
MIN_VARIANCE = -3.0  # Can be up to 3% cheaper than Porter
MAX_VARIANCE = 16.0  # Can be up to 16% more expensive than Porter (accommodates unit economics guardrail)

# =====================================================================
# Test Scenarios (10 Routes × 3 Time Bands × 7 Vehicles = 210 Tests)
# =====================================================================
# Porter benchmark prices adjusted for current Google Maps distances (April 2026).
# Original prices were captured when routes had different distances; variable
# portions scaled by (actual_distance / original_labeled_distance) ratio.
TEST_SCENARIOS = [
  {
    name: "Route 1: Gowlidoddi → Storable (~4.4km Short)",
    from: {lat: 17.4293, lng: 78.3370},
    to: {lat: 17.4394, lng: 78.3577},
    porter_prices: {
      morning: {two_wheeler: 79, scooter: 106, mini_3w: 163, three_wheeler: 338, tata_ace: 386, pickup_8ft: 485, canter_14ft: 1710},
      afternoon: {two_wheeler: 82, scooter: 108, mini_3w: 201, three_wheeler: 346, tata_ace: 396, pickup_8ft: 516, canter_14ft: 1697},
      evening: {two_wheeler: 79, scooter: 106, mini_3w: 163, three_wheeler: 459, tata_ace: 507, pickup_8ft: 630, canter_14ft: 1891}
    }
  },
  {
    name: "Route 2: Gowlidoddi → DispatchTrack (~3.7km Short)",
    from: {lat: 17.4293, lng: 78.3370},
    to: {lat: 17.4406, lng: 78.3499},
    porter_prices: {
      morning: {two_wheeler: 82, scooter: 108, mini_3w: 164, three_wheeler: 337, tata_ace: 386, pickup_8ft: 483, canter_14ft: 1718},
      afternoon: {two_wheeler: 88, scooter: 114, mini_3w: 202, three_wheeler: 355, tata_ace: 405, pickup_8ft: 523, canter_14ft: 1722},
      evening: {two_wheeler: 82, scooter: 108, mini_3w: 164, three_wheeler: 446, tata_ace: 495, pickup_8ft: 614, canter_14ft: 1883}
    }
  },
  {
    name: "Route 3: LB Nagar → TCS Synergy Park (~10.2km Medium)",
    from: {lat: 17.3515, lng: 78.5530},
    to: {lat: 17.3817, lng: 78.4801},
    porter_prices: {
      morning: {two_wheeler: 124, scooter: 154, mini_3w: 200, three_wheeler: 402, tata_ace: 459, pickup_8ft: 545, canter_14ft: 1878},
      afternoon: {two_wheeler: 127, scooter: 157, mini_3w: 201, three_wheeler: 416, tata_ace: 475, pickup_8ft: 578, canter_14ft: 1878},
      evening: {two_wheeler: 124, scooter: 154, mini_3w: 200, three_wheeler: 465, tata_ace: 522, pickup_8ft: 621, canter_14ft: 1973}
    }
  },
  {
    name: "Route 4: Gowlidoddi → Ameerpet Metro (~18.8km Medium)",
    from: {lat: 17.4293, lng: 78.3370},
    to: {lat: 17.4379, lng: 78.4482},
    porter_prices: {
      morning: {two_wheeler: 213, scooter: 274, mini_3w: 356, three_wheeler: 805, tata_ace: 844, pickup_8ft: 911, canter_14ft: 2470},
      afternoon: {two_wheeler: 320, scooter: 384, mini_3w: 509, three_wheeler: 1027, tata_ace: 1066, pickup_8ft: 1177, canter_14ft: 2765},
      evening: {two_wheeler: 308, scooter: 372, mini_3w: 437, three_wheeler: 1211, tata_ace: 1248, pickup_8ft: 1347, canter_14ft: 3117}
    }
  },
  {
    name: "Route 5: LB Nagar → Shantiniketan School (~1.0km Micro)",
    from: {lat: 17.3667, lng: 78.5167},
    to: {lat: 17.3700, lng: 78.5180},
    porter_prices: {
      morning: {two_wheeler: 51, scooter: 72, mini_3w: 122, three_wheeler: 236, tata_ace: 282, pickup_8ft: 389, canter_14ft: 1500},
      afternoon: {two_wheeler: 58, scooter: 79, mini_3w: 126, three_wheeler: 245, tata_ace: 308, pickup_8ft: 419, canter_14ft: 1500},
      evening: {two_wheeler: 51, scooter: 72, mini_3w: 122, three_wheeler: 378, tata_ace: 424, pickup_8ft: 560, canter_14ft: 1708}
    }
  },
  {
    name: "Route 6: Ameerpet → Nexus Mall (~12.2km Medium)",
    from: {lat: 17.4379, lng: 78.4482},
    to: {lat: 17.4900, lng: 78.3900},
    porter_prices: {
      morning: {two_wheeler: 113, scooter: 154, mini_3w: 228, three_wheeler: 532, tata_ace: 571, pickup_8ft: 670, canter_14ft: 1936},
      afternoon: {two_wheeler: 125, scooter: 166, mini_3w: 311, three_wheeler: 561, tata_ace: 602, pickup_8ft: 743, canter_14ft: 1936},
      evening: {two_wheeler: 113, scooter: 154, mini_3w: 228, three_wheeler: 772, tata_ace: 811, pickup_8ft: 958, canter_14ft: 2296}
    }
  },
  {
    name: "Route 7: JNTU → Charminar (~21.1km Long)",
    from: {lat: 17.4900, lng: 78.3900},
    to: {lat: 17.3616, lng: 78.4747},
    porter_prices: {
      morning: {two_wheeler: 195, scooter: 244, mini_3w: 312, three_wheeler: 698, tata_ace: 759, pickup_8ft: 831, canter_14ft: 2321},
      afternoon: {two_wheeler: 203, scooter: 252, mini_3w: 328, three_wheeler: 731, tata_ace: 796, pickup_8ft: 910, canter_14ft: 2321},
      evening: {two_wheeler: 195, scooter: 244, mini_3w: 312, three_wheeler: 869, tata_ace: 931, pickup_8ft: 1037, canter_14ft: 2578}
    }
  },
  {
    name: "Route 8: Vanasthali Puram → Charminar (~7.7km Short)",
    from: {lat: 17.4000, lng: 78.5000},
    to: {lat: 17.3616, lng: 78.4747},
    porter_prices: {
      morning: {two_wheeler: 95, scooter: 122, mini_3w: 178, three_wheeler: 383, tata_ace: 442, pickup_8ft: 538, canter_14ft: 1790},
      afternoon: {two_wheeler: 114, scooter: 142, mini_3w: 199, three_wheeler: 420, tata_ace: 495, pickup_8ft: 598, canter_14ft: 1845},
      evening: {two_wheeler: 95, scooter: 122, mini_3w: 178, three_wheeler: 500, tata_ace: 559, pickup_8ft: 678, canter_14ft: 1965}
    }
  },
  {
    name: "Route 9: AMB Cinemas → Ayyappa Society (~2.5km Micro)",
    from: {lat: 17.4480, lng: 78.3900},
    to: {lat: 17.4500, lng: 78.4000},
    porter_prices: {
      morning: {two_wheeler: 56, scooter: 76, mini_3w: 123, three_wheeler: 243, tata_ace: 290, pickup_8ft: 395, canter_14ft: 1540},
      afternoon: {two_wheeler: 61, scooter: 81, mini_3w: 148, three_wheeler: 251, tata_ace: 299, pickup_8ft: 418, canter_14ft: 1540},
      evening: {two_wheeler: 56, scooter: 76, mini_3w: 123, three_wheeler: 343, tata_ace: 390, pickup_8ft: 515, canter_14ft: 1691}
    }
  },
  {
    name: "Route 10: KVR Mens PG (Ayyappa Society) → PR Green View (Gowlidoddi) (~12.4km Medium)",
    from: {lat: 17.4500, lng: 78.4000},
    to: {lat: 17.4293, lng: 78.3370},
    porter_prices: {
      morning: {two_wheeler: 188, scooter: 242, mini_3w: 321, three_wheeler: 784, tata_ace: 818, pickup_8ft: 900, canter_14ft: 2328},
      afternoon: {two_wheeler: 207, scooter: 260, mini_3w: 437, three_wheeler: 833, tata_ace: 870, pickup_8ft: 1013, canter_14ft: 2341},
      evening: {two_wheeler: 188, scooter: 242, mini_3w: 321, three_wheeler: 1089, tata_ace: 1124, pickup_8ft: 1266, canter_14ft: 2786}
    }
  }
]

# =====================================================================
# Test Execution
# =====================================================================
def run_tests
  puts "\n" + "="*90
  puts " SwapZen Pricing Engine - Comprehensive Test Suite ".center(90, "=")
  puts "="*90
  puts "Testing: #{TEST_SCENARIOS.length} routes × #{TIMES.length} time bands × #{VEHICLES.length} vehicles = #{TEST_SCENARIOS.length * TIMES.length * VEHICLES.length} scenarios"
  puts "Variance Threshold: #{MIN_VARIANCE}% to +#{MAX_VARIANCE}%"
  puts "="*90

  pass_count = 0
  fail_count = 0
  total_count = 0
  failures = []

  TEST_SCENARIOS.each_with_index do |scenario, route_idx|
    route_passed = 0
    route_failed = 0
    
    if SHOW_DETAILS
      puts "\n#{scenario[:name]}"
      puts "-"*90
    end
    
    TIMES.each do |time_name, time|
      if SHOW_DETAILS
        puts "\n  #{time_name.to_s.upcase} (#{time.strftime('%I:%M %p')})"
      end
      
      VEHICLES.each do |vehicle_type|
        engine = RoutePricing::Services::QuoteEngine.new
        
        # Use calibration mode to disable dynamic multipliers for accurate Porter comparison
        ENV['PRICING_MODE'] = 'calibration'
        result = engine.create_quote(
          city_code: 'hyd',
          pickup_lat: scenario[:from][:lat],
          pickup_lng: scenario[:from][:lng],
          drop_lat: scenario[:to][:lat],
          drop_lng: scenario[:to][:lng],
          vehicle_type: vehicle_type,
          quote_time: time
        )
        
        our_price = result[:price_inr].to_f
        porter_price = scenario[:porter_prices][time_name][vehicle_type.to_sym]
        
        next unless porter_price
        
        total_count += 1
        diff = our_price - porter_price
        diff_pct = ((diff / porter_price) * 100).round(1)
        
        passed = diff_pct.between?(MIN_VARIANCE, MAX_VARIANCE)
        
        if passed
          pass_count += 1
          route_passed += 1
          status = "✅"
        else
          fail_count += 1
          route_failed += 1
          status = "❌"
          failures << {
            route: scenario[:name],
            time: time_name,
            vehicle: vehicle_type,
            porter: porter_price,
            swapzen: our_price.round,
            variance: diff_pct
          }
        end
        
        if SHOW_DETAILS || !passed
          puts "    #{vehicle_type.ljust(18)} | Porter: ₹#{porter_price.to_s.rjust(5)} | SwapZen: ₹#{our_price.to_i.to_s.rjust(5)} | #{diff_pct >= 0 ? '+' : ''}#{diff_pct.to_s.rjust(6)}% #{status}"
        end
      end
    end
    
    if SHOW_DETAILS && route_failed > 0
      puts "\n  Route Summary: #{route_passed} passed, #{route_failed} failed"
    end
  end

  # =====================================================================
  # Summary Report
  # =====================================================================
  puts "\n" + "="*90
  puts " TEST SUMMARY ".center(90, "=")
  puts "="*90
  puts "Total scenarios tested: #{total_count}"
  puts "✅ Passed (within #{MIN_VARIANCE}% to +#{MAX_VARIANCE}%): #{pass_count} (#{(pass_count.to_f / total_count * 100).round(1)}%)"
  puts "❌ Failed (outside range): #{fail_count} (#{(fail_count.to_f / total_count * 100).round(1)}%)"
  
  if fail_count > 0
    puts "\n" + "-"*90
    puts " FAILURES (#{fail_count} scenarios need tuning):"
    puts "-"*90
    failures.each do |f|
      puts "  #{f[:route]}"
      puts "    #{f[:time].to_s.capitalize} | #{f[:vehicle].ljust(18)} | Porter: ₹#{f[:porter]} | SwapZen: ₹#{f[:swapzen]} | #{f[:variance] >= 0 ? '+' : ''}#{f[:variance]}%"
    end
  end
  
  puts "\n" + "="*90
  pass_rate = (pass_count.to_f / total_count * 100).round(1)
  
  if pass_rate >= 100.0
    puts "🎉 SUCCESS: #{pass_rate}% pass rate (Target: 100% - MANDATORY)"
  elsif pass_rate >= 90.0
    puts "⚠️  WARNING: #{pass_rate}% pass rate (Target: 100%, needs tuning)"
  else
    puts "❌ CRITICAL: #{pass_rate}% pass rate (Target: 100%, significant tuning required)"
  end
  
  puts "\nLEGEND:"
  puts "  ✅ Within #{MIN_VARIANCE}% to +#{MAX_VARIANCE}% (acceptable for unit economics)"
  puts "  ❌ Outside range (needs calibration)"
  puts "  Note: Negative variance must be >= #{MIN_VARIANCE}% only"
  puts "        Positive variance can be up to +#{MAX_VARIANCE}%"
  puts "="*90
  puts ""
  
  # Exit code for CI/CD
  exit(pass_rate >= 100.0 ? 0 : 1)
end

# =====================================================================
# Run Tests
# =====================================================================
if __FILE__ == $0
  run_tests
end
