# Zen Route Pricing Engine

**Production-grade microservice for hyper-local delivery pricing.**

Calculates competitive delivery costs for SwapZen's marketplace using H3 hexagonal zone grids, 5-tier pricing resolution, and Porter-calibrated rates.

---

## Prerequisites

- Ruby 3.3.6+
- Rails 8.0+
- CockroachDB running on port 26257 (shared with swapzen-api)
- Redis running on port 6379
- Google Maps API Key (Distance Matrix + Directions + Weather APIs enabled)
- swapzen-api migrations already applied (owns the `zones` table)

---

## Installation

```bash
# 1. Clone and install dependencies
cd zen-route-pricing-engine
bundle install

# 2. Configure environment
cp .env.example .env
```

Edit `.env` with your actual values:

```env
SERVICE_API_KEY=zen-route_<generate-with-securerandom>
GOOGLE_MAPS_API_KEY=<your-google-maps-api-key>
DATABASE_URL=postgresql://root@127.0.0.1:26257/swapzen_development?sslmode=disable
REDIS_URL=redis://localhost:6379/0
SECRET_KEY_BASE=<run: rails secret>
PRICING_MODE=production
RAILS_ENV=development
```

> **IMPORTANT:** Use `127.0.0.1` (not `localhost`) in DATABASE_URL. macOS can route `localhost` to IPv6 which won't reach CockroachDB.

```bash
# 3. Run migrations (do NOT run db:create — database already exists)
rails db:migrate

# 4. Sync H3 zone configs from YAML to database
rails zones:h3_sync[hyd]
```

This loads all 90 zones, ~740 H3 cells, vehicle pricing, distance slabs, corridors, weather defaults, min fare overrides, and cancellation rates from `config/zones/hyderabad/h3_zones.yml`.

```bash
# 5. Verify setup
PRICING_MODE=calibration bundle exec ruby script/test_pricing_engine.rb
```

Should show **210 scenarios** with 100% pass rate.

---

## Running the App

```bash
# Start the pricing engine on port 3002
rails server -p 3002
```

The engine is now available at `http://localhost:3002`.

Health check:
```bash
curl http://localhost:3002/up
```

---

## Getting a Price Quote

All API requests require the `X-API-KEY` header matching `SERVICE_API_KEY` in your `.env`.

### Single Vehicle Quote

```bash
curl -X POST http://localhost:3002/route_pricing/create_quote \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{
    "city_code": "hyd",
    "vehicle_type": "three_wheeler",
    "pickup_lat": 17.4400,
    "pickup_lng": 78.3489,
    "drop_lat": 17.3850,
    "drop_lng": 78.4867
  }'
```

**Response:**
```json
{
  "quote_id": "abc-123",
  "price_paise": 25000,
  "price_display": "Rs 250",
  "valid_until": "2026-03-29T10:15:00+05:30",
  "breakdown": {
    "base_fare": 5000,
    "distance_component": 12000,
    "time_component": 3500,
    "dead_km_charge": 0,
    "waiting_charge": 0,
    "weather_condition": "clear",
    "weather_multiplier": 1.0,
    "backhaul_multiplier": 1.0,
    "cancellation_risk_multiplier": 1.0,
    "segment_pricing_used": false,
    "combined_surge": 1.0
  }
}
```

### Multi-Vehicle Quote (all 10 vehicle types at once)

```bash
curl -X POST http://localhost:3002/route_pricing/multi_quote \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{
    "city_code": "hyd",
    "pickup_lat": 17.4400,
    "pickup_lng": 78.3489,
    "drop_lat": 17.3850,
    "drop_lng": 78.4867
  }'
```

### Round Trip Quote

```bash
curl -X POST http://localhost:3002/route_pricing/round_trip_quote \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{
    "city_code": "hyd",
    "vehicle_type": "tata_ace",
    "pickup_lat": 17.4400,
    "pickup_lng": 78.3489,
    "drop_lat": 17.3850,
    "drop_lng": 78.4867
  }'
```

### Validate a Quote

```bash
curl -X POST http://localhost:3002/route_pricing/validate_quote \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{"quote_id": "abc-123"}'
```

### Record Actual Vendor Price

```bash
curl -X POST http://localhost:3002/route_pricing/record_actual \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{
    "quote_id": "abc-123",
    "actual_price_paise": 24000,
    "vendor_code": "porter"
  }'
```

### Vehicle Types

| Category | Code | Description |
|----------|------|-------------|
| Small | `two_wheeler` | Motorcycle delivery |
| Small | `scooter` | Scooter delivery |
| Mid | `mini_3w` | Mini 3-wheeler |
| Mid | `three_wheeler` | Standard auto |
| Mid | `three_wheeler_ev` | Electric auto |
| Mid | `tata_ace` | Tata Ace mini truck |
| Mid | `pickup_8ft` | 8ft pickup |
| Heavy | `eeco` | Maruti Eeco van |
| Heavy | `tata_407` | Tata 407 truck |
| Heavy | `canter_14ft` | 14ft canter truck |

---

## Rollout Flags (Feature Gates)

The pricing engine uses rollout flags to safely enable/disable new pricing accuracy features. All features start **disabled** by default.

### Available Flags

| Flag | What it does | Default |
|------|-------------|---------|
| `route_segment_pricing` | Per-zone pricing for each route segment (vs flat rate) | OFF |
| `weather_pricing` | Rain/storm/fog price multipliers via Google Weather API | OFF |
| `backhaul_pricing` | Empty-return premium for airport/industrial zones | OFF |
| `cancellation_risk_pricing` | Higher prices in high-cancellation zones | OFF |

### Managing Flags via API

**List all flags:**
```bash
curl http://localhost:3002/route_pricing/admin/rollout_flags \
  -H "X-API-KEY: your-service-api-key"
```

**Enable a flag (globally):**
```bash
curl -X POST http://localhost:3002/route_pricing/admin/rollout_flags \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{
    "flag_name": "weather_pricing",
    "enabled": true
  }'
```

**Enable a flag for a specific city:**
```bash
curl -X POST http://localhost:3002/route_pricing/admin/rollout_flags \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: your-service-api-key" \
  -d '{
    "flag_name": "backhaul_pricing",
    "city_code": "hyd",
    "enabled": true
  }'
```

### Managing Flags via Rails Console

```ruby
rails console

# List all flags
PricingRolloutFlag.all.pluck(:flag_name, :city_code, :enabled)

# Enable a flag globally
PricingRolloutFlag.set!('weather_pricing', enabled: true)

# Enable a flag for Hyderabad only
PricingRolloutFlag.set!('weather_pricing', city_code: 'hyd', enabled: true)

# Disable a flag
PricingRolloutFlag.set!('weather_pricing', enabled: false)

# Check if a flag is enabled
PricingRolloutFlag.enabled?('weather_pricing', city_code: 'hyd')
```

### Recommended Rollout Order

1. **cancellation_risk_pricing** — Low risk, small multiplier (1.025x-1.075x)
2. **backhaul_pricing** — Medium risk, affects airport/industrial zones (up to 1.17x)
3. **weather_pricing** — Medium risk, only active during bad weather
4. **route_segment_pricing** — High risk, changes all cross-zone quotes. Test most carefully.

After enabling each flag, run calibration to verify:
```bash
PRICING_MODE=calibration bundle exec ruby script/test_pricing_engine.rb
```

> In calibration mode, all dynamic factors (weather, backhaul, cancellation, surge) are automatically bypassed, so calibration results remain stable.

---

## Architecture

### H3 Zone System

All zones are defined by H3 R7 hexagonal cells. The single source of truth is `config/zones/hyderabad/h3_zones.yml`.

- **90 zones** in Hyderabad (76 manual + 14 auto-generated)
- **~740 H3 R7 cells** mapped to zones
- **O(1) zone lookup** via in-memory H3 map
- **12 zone types** with priority-based resolution

### Pricing Resolution Hierarchy (5-tier)

1. **Corridor Override** — Explicit zone-pair pricing (77 pairs, highest priority)
2. **Inter-Zone Formula** — Weighted 60/40 average of origin/destination zones
3. **Zone-Time Override** — Zone-specific time-band rates (morning/afternoon/evening)
4. **Zone Override** — Base zone rates
5. **City Default** — Fallback global rates (10 PricingConfig records)

### Price Calculation Pipeline

```
base_fare
+ distance_component (telescoping slabs or per-zone segment pricing)
+ time_component (per-minute rate x duration)
+ dead_km_charge (pickup distance beyond free radius)
+ waiting_charge (estimated loading/unloading time)
x distance_band_multiplier
x traffic_multiplier
x zone_type_multiplier
x weather_multiplier (rain/fog/storm)
x backhaul_multiplier (empty-return premium)
x cancellation_risk_multiplier
x surge_multiplier
-> guardrail check (5% minimum margin)
-> round to nearest Rs 10
```

### 10 Vehicle Types

| Category | Vehicles |
|----------|----------|
| **Small** | two_wheeler, scooter |
| **Mid** | mini_3w, three_wheeler, three_wheeler_ev, tata_ace, pickup_8ft |
| **Heavy** | eeco, tata_407, canter_14ft |

---

## Zone Management

```bash
# Primary: H3-based sync (source of truth)
rails zones:h3_export[hyd]                     # Export DB -> h3_zones.yml
rails zones:h3_sync[hyd]                       # Sync h3_zones.yml -> DB
FORCE_PRICING=true rails zones:h3_sync[hyd]    # Force overwrite pricing

# Inspection
rails zones:list city=hyd       # List zones
rails zones:pricing city=hyd    # Pricing stats
rails zones:corridors city=hyd  # Corridor stats

# Corridor analysis (report only)
rails corridors:analyze[hyd,30]  # Top 50 zone pairs by volume over last 30 days
```

### Config Structure

```
config/zones/
├── hyderabad.yml                  # Legacy bbox zone definitions
└── hyderabad/
    ├── h3_zones.yml               # H3 zone definitions + pricing (SOURCE OF TRUTH)
    ├── vehicle_defaults.yml       # Global rates, slabs, inter-zone formula
    ├── hyderabad_auto_zone.yml    # Auto-zone generation config
    └── corridors/                 # Corridor pricing (77 zone pairs)
```

---

## Rake Tasks

```bash
# Zone management
rails zones:h3_sync[hyd]              # Sync YAML -> DB (zones, H3, pricing, configs, slabs)
rails zones:h3_export[hyd]            # Export DB -> YAML
FORCE_PRICING=true rails zones:h3_sync[hyd]  # Force overwrite existing pricing
rails zones:list city=hyd             # List all zones
rails zones:pricing city=hyd          # Show pricing stats
rails zones:corridors city=hyd        # Show corridor stats
rails zones:populate_h3[hyd]          # Populate H3 mappings from zone bboxes
rails zones:seed_supply_density[hyd]  # Seed supply density per H3 cell

# Pricing tools
rails pricing:seed_distance_slabs     # Seed distance slabs from vehicle_defaults
rails pricing:recalibrate             # Recalibrate against Porter benchmarks

# Corridor analysis
rails corridors:analyze[hyd,30]       # Analyze top zone pairs (last N days)
```

---

## Testing

### Porter Benchmark Test

```bash
PRICING_MODE=calibration bundle exec ruby script/test_pricing_engine.rb
```

**210 scenarios** (10 routes x 3 time bands x 7 vehicles) — **100% Pass Rate**

---

## Admin API Endpoints

All admin endpoints are under `/route_pricing/admin/` and require the `X-API-KEY` header.

### Config Management
- `GET /route_pricing/admin/list_configs` — List pricing configs
- `PATCH /route_pricing/admin/update_config` — Update config (creates draft)
- `POST /route_pricing/admin/submit_for_approval` — Submit draft for approval
- `POST /route_pricing/admin/approve_config` — Approve config
- `POST /route_pricing/admin/reject_config` — Reject config

### Surge Management
- `POST /route_pricing/admin/create_surge_rule` — Create surge rule
- `PATCH /route_pricing/admin/deactivate_surge_rule` — Deactivate surge
- `GET /route_pricing/admin/surge_buckets` — List H3 surge buckets
- `POST /route_pricing/admin/surge_buckets` — Create surge bucket
- `GET /route_pricing/admin/surge_buckets/heatmap` — Surge heatmap

### Control Plane
- `GET /route_pricing/admin/rollout_flags` — List rollout flags
- `POST /route_pricing/admin/rollout_flags` — Set rollout flag
- `GET /route_pricing/admin/change_logs` — Audit trail
- `POST /route_pricing/admin/emergency_freeze` — Freeze city pricing
- `DELETE /route_pricing/admin/emergency_freeze` — Unfreeze
- `GET /route_pricing/admin/freeze_status` — Check freeze status

### Analytics
- `GET /route_pricing/admin/drift_report` — Quote vs actual drift
- `GET /route_pricing/admin/drift_summary` — Drift summary
- `GET /route_pricing/admin/market/dashboard` — Market dashboard
- `GET /route_pricing/admin/market/zone_health` — Zone health
- `GET /route_pricing/admin/market/pressure_map` — Demand pressure map
- `GET /route_pricing/admin/margin_report` — Margin analytics

### Backtesting
- `POST /route_pricing/admin/backtests` — Run backtest
- `GET /route_pricing/admin/backtests` — List backtests
- `GET /route_pricing/admin/backtests/:id` — Backtest detail

### Zone & Map
- `PATCH /route_pricing/admin/zones/:id/toggle` — Toggle zone active
- `GET /route_pricing/admin/zone_map/zones` — Zone boundaries
- `GET /route_pricing/admin/zone_map/corridors` — Corridor map
- `POST /route_pricing/admin/auto_zones/generate` — Generate auto-zones
- `DELETE /route_pricing/admin/auto_zones/remove` — Remove auto-zones
- `PATCH /route_pricing/admin/auto_zones/toggle_cell` — Toggle hex cell

### Vendor & Merchant
- `POST /route_pricing/admin/sync_vendor_rates` — Sync vendor rates
- `GET /route_pricing/admin/vendor_rate_cards` — List vendor cards
- `GET /route_pricing/admin/merchant_policies` — List merchant policies
- `POST /route_pricing/admin/merchant_policies` — Create policy
- `POST /route_pricing/admin/merchant_policies/simulate` — Simulate policy

### Porter Benchmarks
- `GET /route_pricing/admin/porter_benchmarks` — List benchmarks
- `POST /route_pricing/admin/porter_benchmarks/bulk_save` — Bulk save
- `POST /route_pricing/admin/porter_benchmarks/recalibrate` — Recalibrate

### Route Matrix
- `GET /route_pricing/admin/route_matrix` — Route pricing matrix
- `GET /route_pricing/admin/route_matrix/landmark_routes` — Landmark routes
- `GET /route_pricing/admin/route_matrix/calibration_routes` — Calibration routes
- `POST /route_pricing/admin/route_matrix/generate_quote` — Generate quote for route

---

## Database Schema (Key Tables)

| Table | Purpose |
|-------|---------|
| zones | Zone definitions (bbox + H3 indexes) |
| zone_h3_mappings | H3 R7/R8 cell -> zone mappings |
| zone_vehicle_pricings | Base rates per zone x vehicle |
| zone_vehicle_time_pricings | Time-band overrides |
| zone_pair_vehicle_pricings | Corridor pricing |
| pricing_configs | City defaults per vehicle (approval workflow) |
| pricing_distance_slabs | Telescoping per-km rates |
| inter_zone_configs | Inter-zone formula weights |
| vendor_rate_cards | Vendor cost prediction rates |
| pricing_quote_decisions | Quote audit log + drift |
| pricing_backtests | Backtest results |
| pricing_outcomes | Accepted/rejected/expired tracking |
| pricing_rollout_flags | Feature gates by city/vehicle |
| pricing_emergency_freezes | City-level freeze switch |
| merchant_pricing_policies | Merchant overrides |
| backhaul_probabilities | Zone return probability data |
| h3_surge_buckets | Per-cell surge multipliers |
| h3_supply_densities | Per-cell pickup distance estimates |

---

## Documentation

- [Engine Design](docs/ENGINE_DESIGN.md) — Architecture and component details
- [Pricing Calculation Guide](docs/pricing-calculation-guide.md) — Detailed formula walkthrough
- [Zone Configuration](config/zones/README.md) — YAML format and sync commands
- [Pricing Backlog](docs/SWAPZEN_PRICING_BACKLOG.md) — Feature roadmap
- [Platform Plan](docs/SWAPZEN_HYPERLOCAL_PRICING_PLATFORM_PLAN.md) — Long-term vision
