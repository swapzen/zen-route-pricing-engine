# Pricing Engine Test Scripts

## Main Test Script

### `test_pricing_engine.rb` - Comprehensive Test Suite

**Single script to test all pricing scenarios against Porter benchmarks.**

#### Usage:

```bash
# Full test (shows all scenarios)
bundle exec rails runner script/test_pricing_engine.rb

# With Google Maps (recommended for accurate distances)
ROUTE_PROVIDER_STRATEGY=google bundle exec rails runner script/test_pricing_engine.rb

# Quick mode (only shows failures)
bundle exec rails runner script/test_pricing_engine.rb --quick
```

#### What it tests:
- **10 routes** × **3 time bands** × **7 vehicle types** = **210 scenarios**
- Compares SwapZen prices vs Porter benchmarks
- Variance threshold: **-3% to +15%** (unit economics constraint)
- Target: **90%+ pass rate**

#### Output:
- ✅ Pass: Within -3% to +15% variance
- ❌ Fail: Outside acceptable range
- Summary statistics and failure details

#### Before running:
1. Ensure database is seeded: `bundle exec rails db:seed`
2. Ensure all migrations are run: `bundle exec rails db:migrate`

---

## Other Scripts

### Verification Scripts
- `verify_features_active.rb` - Verify distance band multipliers and time-band pricing are active
- `verify_hyderabad_zones.rb` - Verify zone boundaries and mappings
- `verify_zones.rb` - General zone verification

### Setup Scripts
- `setup_zone_pricing_configs.rb` - Initialize zone-level pricing configurations
- `setup_porter_aligned_pricing.rb` - Setup Porter-aligned pricing
- `setup_new_zone_pricing.rb` - Setup new zone pricing
- `setup_corridors.rb` - Setup corridor pricing

### Utility Scripts
- `generate_test_routes.rb` - Generate test route data
- `test_google_api.rb` - Test Google Maps API connectivity
- `test_provider.rb` - Test route provider functionality
- `cleanup_unnecessary_files.rb` - Clean up temporary files

---

## Notes

- All test scripts use IST timezone (Asia/Kolkata)
- Porter benchmarks are the source of truth for calibration
- Negative variance must be >= -3% only (unit economics constraint)
- Positive variance can be up to +15% (market competitiveness)
