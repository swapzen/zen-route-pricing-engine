@../CLAUDE.md

# Zen Route Pricing Engine

## Stack

- Rails 8.0.4, Ruby 3.3.6, API-only, CockroachDB, Redis
- H3 hexagonal grid (gem v3.7) for zone boundaries
- YAML-driven zone configs under `config/zones/`
- Single source of truth: `config/zones/{city}/h3_zones.yml`

## Architecture

- 5-tier pricing hierarchy: Corridor > Inter-Zone > Zone-Time > Zone > City Default
- QuoteEngine → RouteResolver → PriceCalculator + ZonePricingResolver
- Vehicle categories defined ONLY in `app/services/route_pricing/vehicle_categories.rb`
- Inter-zone uses weighted average (60% origin, 40% destination by default)
- H3-first zone resolution (R7 lookup → R8 boundary disambiguation → bbox fallback)

## Zone System (H3-based)

- 90 zones in Hyderabad (76 manual + 14 auto-generated)
- All zones defined by H3 R7 hex cells in `h3_zones.yml`
- ~740 H3 R7 cells mapped to zones
- Zone types: tech_corridor, business_cbd, airport_logistics, residential_growth, residential_dense, residential_mixed, traditional_commercial, premium_residential, industrial, heritage_commercial, outer_ring, default
- Sync command: `rails zones:h3_sync[hyd]` (loads h3_zones.yml → DB)
- Export command: `rails zones:h3_export[hyd]` (DB → h3_zones.yml)

## Key Services

- `H3ZoneConfigLoader` — reads h3_zones.yml → syncs zones, H3 mappings, pricing, city defaults, distance slabs, inter-zone config to DB
- `H3ZoneResolver` — O(1) H3 hex lookup for zone resolution (R7 cache → R8 boundary)
- `ZonePricingResolver` — 5-tier pricing resolution
- `PriceCalculator` — base_fare + distance slabs + per-min + dead-km + multipliers
- `VendorPayoutCalculator` — vendor cost prediction (two-sided pricing)
- `DriftAnalyzer` — quote vs actual drift detection
- `BacktestRunner` — replay quotes against candidate configs
- `MarketStateAggregator` — acceptance/rejection/expiry rates
- `CandidatePriceOptimizer` — shadow model scoring

## Vehicle Categories (exact code values)

- SMALL: two_wheeler, scooter
- MID: mini_3w, three_wheeler, three_wheeler_ev, tata_ace, pickup_8ft
- HEAVY: eeco, tata_407, canter_14ft

## Time Bands

- morning: 6:00-12:00, afternoon: 12:00-18:00, evening: 18:00-6:00
- MUST use city timezone (e.g., Asia/Kolkata)

## Config File Structure

```
config/zones/
├── hyderabad.yml                  # Legacy bbox zone definitions (76 manual)
└── hyderabad/
    ├── h3_zones.yml               # H3 zone definitions + pricing (SOURCE OF TRUTH)
    ├── vehicle_defaults.yml       # Global rates, slabs, inter-zone formula
    ├── hyderabad_auto_zone.yml    # Auto-zone generation config
    ├── pricing/                   # Legacy per-zone pricing YAML (6 zones)
    └── corridors/                 # Corridor pricing (77 zone pairs)
        ├── priority_corridors.yml
        ├── route_4_fin_to_ameerpet.yml
        └── route_matrix_8band.yml
```

## API Endpoints

### Quote APIs
- POST /route_pricing/create_quote — Single quote
- POST /route_pricing/multi_quote — All vehicle types
- POST /route_pricing/round_trip_quote — Round trip
- POST /route_pricing/validate_quote — Check validity
- POST /route_pricing/record_actual — Log vendor price

### Admin APIs
- PATCH /route_pricing/admin/configs/:id — Update config (approval workflow)
- POST /route_pricing/admin/configs/:id/approve — Approve config
- POST /route_pricing/admin/configs/:id/reject — Reject config
- GET /route_pricing/admin/configs — List configs
- POST /route_pricing/admin/create_surge_rule — Create surge rule
- DELETE /route_pricing/admin/deactivate_surge_rule — Deactivate surge
- GET /route_pricing/admin/cells — H3 hex cells for zone map
- PATCH /route_pricing/admin/toggle_cell — Toggle cell serviceability
- POST /route_pricing/admin/auto_zones/generate — Generate auto-zones
- DELETE /route_pricing/admin/auto_zones/remove — Remove auto-zones
- PATCH /route_pricing/admin/zones/:id/toggle — Toggle zone active
- POST /route_pricing/admin/sync_vendor_rates — Sync vendor rates
- GET /route_pricing/admin/vendor_rate_cards — List vendor cards
- GET /route_pricing/admin/margin_report — Margin analytics
- GET /route_pricing/admin/drift — Drift analysis
- POST /route_pricing/admin/backtests — Run backtest
- GET /route_pricing/admin/market_state — Market state
- GET /route_pricing/admin/control_plane — Change logs, flags, freezes
- GET /route_pricing/admin/merchant_policies — Merchant policies

### Auth
- X-API-KEY header (SERVICE_API_KEY env var)

## Caching

- Redis with 2-hour TTL (fallback to memory store if REDIS_URL not set)
- Cache key includes time bucket for freshness
- H3ZoneResolver maintains in-memory R7/R8 maps (invalidated on sync)

## Testing

- Canonical test: `script/test_pricing_engine.rb`
- Run: `PRICING_MODE=calibration RAILS_ENV=development bundle exec ruby script/test_pricing_engine.rb`
- 210 test scenarios (10 routes x 3 time bands x 7 vehicles)
- Google Maps distances drift — recalibration needed periodically
- Unit economics guardrail adds ~7% (2% PG + Rs 2 support + 5% margin)

## Database

- Shared `swapzen_development` on CockroachDB
- `zones` table created by swapzen-api — DO NOT create it here
- Pricing engine adds columns via ALTER TABLE migrations
- Before seeding: clear FK dependencies (zone_locations, etc.)

### Key Tables
- zones — Zone definitions (bbox + H3 indexes)
- zone_h3_mappings — H3 R7/R8 cell → zone mappings
- zone_vehicle_pricings — Base rates per zone × vehicle
- zone_vehicle_time_pricings — Time-band overrides
- zone_pair_vehicle_pricings — Corridor pricing
- pricing_configs — City defaults per vehicle (approval workflow)
- pricing_distance_slabs — Telescoping per-km rates
- vendor_rate_cards — Vendor cost prediction rates
- pricing_quote_decisions — Quote audit log + drift columns
- pricing_backtests — Backtest results
- pricing_change_logs — Audit trail
- pricing_rollout_flags — Feature gates by city/vehicle
- pricing_emergency_freezes — City-level freeze switch
- pricing_outcomes — Accepted/rejected/expired tracking
- merchant_pricing_policies — Merchant overrides
- pricing_model_configs — Shadow model definitions
- pricing_model_scores — Shadow model scores per quote
- h3_supply_densities — Per-cell pickup distance estimates
- inter_zone_configs — Inter-zone formula weights + adjustments

## Rake Tasks

```bash
# H3 zone management (primary)
rails zones:h3_export[hyd]        # Export DB → h3_zones.yml
rails zones:h3_sync[hyd]          # Sync h3_zones.yml → DB (zones, H3, pricing, configs, slabs)
FORCE_PRICING=true rails zones:h3_sync[hyd]  # Force overwrite pricing

# Legacy zone sync
rails zones:sync city=hyd          # Sync from legacy YAML
rails zones:list city=hyd          # List zones
rails zones:pricing city=hyd       # Show pricing stats
rails zones:corridors city=hyd     # Show corridor stats

# H3 cell management
rails zones:populate_h3[hyd]       # Populate H3 mappings from zone bboxes
rails zones:seed_supply_density[hyd]  # Seed supply density

# Pricing helpers
rails pricing:seed_distance_slabs   # Seed distance slabs from vehicle_defaults
rails pricing:recalibrate           # Recalibrate against Porter benchmarks
```

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
- Do NOT add "Co-Authored-By" lines to commit messages
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
- **H3 mappings**: After zone changes, verify H3ZoneResolver cache is invalidated
- **Ruby syntax**: Verify `end` keywords balance with `def/class/module/do/if/unless/case`

## Don'ts

- Never hardcode vehicle categories — use `vehicle_categories.rb`
- Never modify zones table structure — owned by swapzen-api
- Never change inter-zone rates without YAML update
- Never bypass H3ZoneConfigLoader for bulk zone/pricing changes — it handles all cascading updates
