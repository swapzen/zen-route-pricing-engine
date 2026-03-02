@../CLAUDE.md

# Zen Route Pricing Engine

## Stack

- Rails 8.0.4, Ruby 3.3.6, API-only, CockroachDB, Redis
- YAML-driven zone configs under `config/zones/`

## Architecture

- 5-tier pricing hierarchy: Corridor > Inter-Zone > Zone-Time > Zone > City Default
- QuoteEngine → RouteResolver → PriceCalculator + ZonePricingResolver
- Vehicle categories defined ONLY in `app/services/route_pricing/vehicle_categories.rb`
- Inter-zone uses weighted average (60% origin, 40% destination by default)

## Vehicle Categories (exact code values)

- SMALL: two_wheeler, scooter
- MID: mini_3w, three_wheeler, three_wheeler_ev, tata_ace, pickup_8ft
- HEAVY: eeco, tata_407, canter_14ft

## Time Bands

- morning: 6:00-12:00, afternoon: 12:00-18:00, evening: 18:00-6:00
- MUST use city timezone (e.g., Asia/Kolkata)

## API Endpoints

- POST /route_pricing/create_quote — Single quote
- POST /route_pricing/multi_quote — All vehicle types
- POST /route_pricing/round_trip_quote — Round trip
- POST /route_pricing/validate_quote — Check validity
- POST /route_pricing/record_actual — Log vendor price
- Admin: update_config, create_surge_rule, list_configs, deactivate_surge_rule
- Auth: X-API-KEY header (SERVICE_API_KEY env var)

## Caching

- Redis with 2-hour TTL (fallback to memory store if REDIS_URL not set)
- Cache key includes time bucket for freshness

## Testing

- Canonical test: `script/test_pricing_engine.rb`
- Run: `PRICING_MODE=calibration RAILS_ENV=development bundle exec ruby script/test_pricing_engine.rb`
- 210 test scenarios (10 routes x 3 time bands x 7 vehicles)
- Google Maps distances drift — recalibration needed periodically
- Unit economics guardrail adds ~7% (2% PG + ₹2 support + 5% margin)

## Database

- Shared `swapzen_development` on CockroachDB
- `zones` table created by swapzen-api — DO NOT create it here
- Pricing engine adds columns via ALTER TABLE migrations
- Before seeding: clear FK dependencies (zone_locations, etc.)

## Database Safety

- NEVER drop, delete, or create databases/tables without explicit user approval
- NEVER run destructive migrations — always show migration code first
- `zones` table owned by swapzen-api — DO NOT modify its structure here
- Before seeding: must clear FK dependencies first — ask user before proceeding

## Secrets & Environment Files (CRITICAL)

- NEVER edit, overwrite, or create .env files — only suggest changes for the user to make manually
- NEVER log, print, echo, or display API keys, tokens, or secrets
- NEVER commit .env, credentials, or any file containing secrets

## Git & Deployment Safety

- Only commit when asked, NEVER git push without explicit user permission
- NEVER force push, NEVER run commands with RAILS_ENV=production
- NEVER reference or connect to production URLs from local dev

## Post-Change Verification (stack-specific)

In addition to the parent verification rules, check these pricing engine-specific items:

- **YAML config structure**: Verify `config/zones/*.yml` files have valid YAML syntax and expected keys
- **Vehicle categories**: All vehicle type references MUST use values from `vehicle_categories.rb` — never hardcode
- **Pricing hierarchy**: If modifying pricing logic, trace the 5-tier fallback: Corridor > Inter-Zone > Zone-Time > Zone > City Default
- **QuoteEngine flow**: Trace QuoteEngine → RouteResolver → PriceCalculator + ZonePricingResolver path
- **Time band logic**: Verify time comparisons use city timezone (Asia/Kolkata), bands: morning 6-12, afternoon 12-18, evening 18-6
- **Redis cache keys**: If changing cache logic, verify key format includes time bucket and cache invalidation still works
- **API response format**: Verify JSON response structure matches what swapzen-api and swapzen-admin expect
- **Ruby syntax**: Verify `end` keywords balance with `def/class/module/do/if/unless/case`

## Don'ts

- Never hardcode vehicle categories — use `vehicle_categories.rb`
- Never modify zones table structure — owned by swapzen-api
- Never change inter-zone rates without YAML update
