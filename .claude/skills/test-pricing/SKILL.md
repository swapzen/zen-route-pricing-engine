---
name: test-pricing
description: Run the canonical pricing engine calibration test against Porter benchmarks
user-invocable: true
argument-hint: "[optional: specific test like 'hsr-layout' or 'inter-zone']"
---

# Run Pricing Engine Calibration Test

Run the canonical pricing engine test to verify pricing accuracy against Porter benchmarks.

## Steps

1. Run the calibration test:
   ```
   PRICING_MODE=calibration RAILS_ENV=development bundle exec ruby script/test_pricing_engine.rb
   ```

2. Analyze the output:
   - Look for scenarios where our price deviates >15% from Porter
   - Identify any FAIL results vs PASS
   - Check the overall pass rate percentage

3. If the user provided specific arguments like a zone or route name, filter the results to focus on those scenarios.

4. Summarize:
   - Total scenarios tested
   - Pass/fail count and percentage
   - Top 5 worst deviations (if any failures)
   - Whether recalibration is needed (Google Maps distances drift over time)

## Notes
- The test uses Google Maps for real distances — results may vary slightly between runs
- Unit economics guardrail adds ~7% (2% PG + ₹2 support + 5% margin)
- Vehicle categories: SMALL (two_wheeler, scooter), MID (mini_three_wheeler, three_wheeler, three_wheeler_ev, tata_ace, pickup_8ft), HEAVY (eeco, tata_407, canter_14ft)
