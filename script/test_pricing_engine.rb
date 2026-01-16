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
  evening:   Time.zone.parse('2026-01-15 23:00')
}

VEHICLES = %w[two_wheeler scooter mini_3w three_wheeler tata_ace pickup_8ft canter_14ft]

# Variance thresholds
MIN_VARIANCE = -3.0  # Can be up to 3% cheaper than Porter
MAX_VARIANCE = 16.0  # Can be up to 16% more expensive than Porter (accommodates unit economics guardrail)

# =====================================================================
# Test Scenarios (10 Routes × 3 Time Bands × 7 Vehicles = 210 Tests)
# =====================================================================
TEST_SCENARIOS = [
  {
    name: "Route 1: Gowlidoddi → Storable (7.3km Short)",
    from: {lat: 17.4293, lng: 78.3370},
    to: {lat: 17.4394, lng: 78.3577},
    porter_prices: {
      morning: {two_wheeler: 100, scooter: 136, mini_3w: 205, three_wheeler: 454, tata_ace: 496, pickup_8ft: 594, canter_14ft: 1848},
      afternoon: {two_wheeler: 105, scooter: 140, mini_3w: 267, three_wheeler: 468, tata_ace: 512, pickup_8ft: 646, canter_14ft: 1826},
      evening: {two_wheeler: 100, scooter: 136, mini_3w: 205, three_wheeler: 654, tata_ace: 696, pickup_8ft: 834, canter_14ft: 2148}
    }
  },
  {
    name: "Route 2: Gowlidoddi → DispatchTrack (6.8km Short)",
    from: {lat: 17.4293, lng: 78.3370},
    to: {lat: 17.4406, lng: 78.3499},
    porter_prices: {
      morning: {two_wheeler: 111, scooter: 148, mini_3w: 216, three_wheeler: 482, tata_ace: 524, pickup_8ft: 619, canter_14ft: 1899},
      afternoon: {two_wheeler: 121, scooter: 158, mini_3w: 287, three_wheeler: 516, tata_ace: 560, pickup_8ft: 692, canter_14ft: 1906},
      evening: {two_wheeler: 111, scooter: 148, mini_3w: 216, three_wheeler: 682, tata_ace: 724, pickup_8ft: 859, canter_14ft: 2199}
    }
  },
  {
    name: "Route 3: LB Nagar → TCS Synergy Park (32.6km Long)",
    from: {lat: 17.3515, lng: 78.5530},
    to: {lat: 17.3817, lng: 78.4801},
    porter_prices: {
      morning: {two_wheeler: 291, scooter: 358, mini_3w: 417, three_wheeler: 928, tata_ace: 986, pickup_8ft: 1042, canter_14ft: 2705},
      afternoon: {two_wheeler: 301, scooter: 368, mini_3w: 422, three_wheeler: 974, tata_ace: 1035, pickup_8ft: 1145, canter_14ft: 2704},
      evening: {two_wheeler: 291, scooter: 358, mini_3w: 417, three_wheeler: 1128, tata_ace: 1186, pickup_8ft: 1282, canter_14ft: 3005}
    }
  },
  {
    name: "Route 4: Gowlidoddi → Ameerpet Metro (15.9km Medium)",
    from: {lat: 17.4293, lng: 78.3370},
    to: {lat: 17.4379, lng: 78.4482},
    porter_prices: {
      morning: {two_wheeler: 188, scooter: 241, mini_3w: 317, three_wheeler: 706, tata_ace: 748, pickup_8ft: 820, canter_14ft: 2321},
      afternoon: {two_wheeler: 278, scooter: 334, mini_3w: 446, three_wheeler: 894, tata_ace: 936, pickup_8ft: 1045, canter_14ft: 2571},
      evening: {two_wheeler: 268, scooter: 324, mini_3w: 385, three_wheeler: 1050, tata_ace: 1090, pickup_8ft: 1189, canter_14ft: 2869}
    }
  },
  {
    name: "Route 5: LB Nagar → Shantiniketan School (1.4km Micro)",
    from: {lat: 17.3667, lng: 78.5167},
    to: {lat: 17.3700, lng: 78.5180},
    porter_prices: {
      morning: {two_wheeler: 52, scooter: 77, mini_3w: 131, three_wheeler: 266, tata_ace: 308, pickup_8ft: 418, canter_14ft: 1492},
      afternoon: {two_wheeler: 62, scooter: 87, mini_3w: 137, three_wheeler: 279, tata_ace: 345, pickup_8ft: 460, canter_14ft: 1492},
      evening: {two_wheeler: 52, scooter: 77, mini_3w: 131, three_wheeler: 466, tata_ace: 508, pickup_8ft: 658, canter_14ft: 1792}
    }
  },
  {
    name: "Route 6: Ameerpet → Nexus Mall (10.2km Short)",
    from: {lat: 17.4379, lng: 78.4482},
    to: {lat: 17.4900, lng: 78.3900},
    porter_prices: {
      morning: {two_wheeler: 102, scooter: 138, mini_3w: 207, three_wheeler: 470, tata_ace: 512, pickup_8ft: 611, canter_14ft: 1863},
      afternoon: {two_wheeler: 112, scooter: 148, mini_3w: 276, three_wheeler: 494, tata_ace: 538, pickup_8ft: 672, canter_14ft: 1863},
      evening: {two_wheeler: 102, scooter: 138, mini_3w: 207, three_wheeler: 670, tata_ace: 712, pickup_8ft: 851, canter_14ft: 2163}
    }
  },
  {
    name: "Route 7: JNTU → Charminar (24.6km Long)",
    from: {lat: 17.4900, lng: 78.3900},
    to: {lat: 17.3616, lng: 78.4747},
    porter_prices: {
      morning: {two_wheeler: 219, scooter: 274, mini_3w: 347, three_wheeler: 786, tata_ace: 848, pickup_8ft: 916, canter_14ft: 2456},
      afternoon: {two_wheeler: 229, scooter: 284, mini_3w: 365, three_wheeler: 825, tata_ace: 891, pickup_8ft: 1007, canter_14ft: 2456},
      evening: {two_wheeler: 219, scooter: 274, mini_3w: 347, three_wheeler: 986, tata_ace: 1048, pickup_8ft: 1156, canter_14ft: 2756}
    }
  },
  {
    name: "Route 8: Vanasthali Puram → Charminar (13.2km Medium)",
    from: {lat: 17.4000, lng: 78.5000},
    to: {lat: 17.3616, lng: 78.4747},
    porter_prices: {
      morning: {two_wheeler: 129, scooter: 167, mini_3w: 234, three_wheeler: 543, tata_ace: 603, pickup_8ft: 696, canter_14ft: 1998},
      afternoon: {two_wheeler: 161, scooter: 200, mini_3w: 270, three_wheeler: 606, tata_ace: 693, pickup_8ft: 799, canter_14ft: 2092},
      evening: {two_wheeler: 129, scooter: 167, mini_3w: 234, three_wheeler: 743, tata_ace: 803, pickup_8ft: 936, canter_14ft: 2298}
    }
  },
  {
    name: "Route 9: AMB Cinemas → Ayyappa Society (4.9km Micro)",
    from: {lat: 17.4480, lng: 78.3900},
    to: {lat: 17.4500, lng: 78.4000},
    porter_prices: {
      morning: {two_wheeler: 64, scooter: 91, mini_3w: 146, three_wheeler: 324, tata_ace: 361, pickup_8ft: 471, canter_14ft: 1580},
      afternoon: {two_wheeler: 74, scooter: 101, mini_3w: 195, three_wheeler: 340, tata_ace: 379, pickup_8ft: 518, canter_14ft: 1580},
      evening: {two_wheeler: 64, scooter: 91, mini_3w: 146, three_wheeler: 524, tata_ace: 561, pickup_8ft: 711, canter_14ft: 1880}
    }
  },
  {
    name: "Route 10: KVR Mens PG (Ayyappa Society) → PR Green View (Gowlidoddi) (8.1km Short)",
    from: {lat: 17.4500, lng: 78.4000},
    to: {lat: 17.4293, lng: 78.3370},
    porter_prices: {
      morning: {two_wheeler: 140, scooter: 179, mini_3w: 245, three_wheeler: 569, tata_ace: 611, pickup_8ft: 699, canter_14ft: 2042},
      afternoon: {two_wheeler: 152, scooter: 191, mini_3w: 321, three_wheeler: 601, tata_ace: 645, pickup_8ft: 773, canter_14ft: 2051},
      evening: {two_wheeler: 140, scooter: 179, mini_3w: 245, three_wheeler: 769, tata_ace: 811, pickup_8ft: 939, canter_14ft: 2342}
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
