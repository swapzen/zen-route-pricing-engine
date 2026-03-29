# Zen Route Pricing Engine

**Production-grade microservice for hyper-local delivery pricing.**

Calculates competitive delivery costs for SwapZen's marketplace using H3 hexagonal zone grids, 5-tier pricing resolution, and Porter-calibrated rates.

---

## Quick Start

### Prerequisites
- Ruby 3.3.6+
- Rails 8.0+
- CockroachDB (Postgres-compatible)
- Redis (for route caching)
- Google Maps API Key

### Setup

```bash
# 1. Install dependencies
bundle install

# 2. Configure environment variables
cp .env.example .env
nano .env  # Add your actual keys

# 3. Configure database (shared with swapzen-api)
# Edit .env: DATABASE_URL=postgresql://root@127.0.0.1:26257/swapzen_development

# 4. Run migrations
rails db:migrate

# 5. Sync H3 zone configurations from YAML
rails zones:h3_sync[hyd]

# 6. Start server
rails server -p 3002
```

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

### Price Calculation

```
base_fare
+ distance_component (telescoping slabs: 4 tiers per vehicle)
+ time_component (per-minute rate × duration)
+ dead_km_charge (pickup distance beyond free radius)
× distance_band_multiplier
× traffic_multiplier
× zone_type_multiplier
→ guardrail check (5% minimum margin)
→ round to nearest Rs 10
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
rails zones:h3_export[hyd]                     # Export DB → h3_zones.yml
rails zones:h3_sync[hyd]                       # Sync h3_zones.yml → DB
FORCE_PRICING=true rails zones:h3_sync[hyd]    # Force overwrite pricing

# Inspection
rails zones:list city=hyd       # List zones
rails zones:pricing city=hyd    # Pricing stats
rails zones:corridors city=hyd  # Corridor stats
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

## Testing

### Porter Benchmark Test

```bash
PRICING_MODE=calibration bundle exec ruby script/test_pricing_engine.rb
```

**210 scenarios** (10 routes x 3 time bands x 7 vehicles) — **100% Pass Rate**

---

## API Endpoints

### Quote APIs
- `POST /route_pricing/create_quote` — Single vehicle quote
- `POST /route_pricing/multi_quote` — All vehicle types
- `POST /route_pricing/round_trip_quote` — Round trip
- `POST /route_pricing/validate_quote` — Check validity
- `POST /route_pricing/record_actual` — Log vendor price

### Admin APIs
- Config management with approval workflow
- H3 hex cell management (view, toggle serviceability)
- Auto-zone generation and removal
- Vendor rate card sync and margin report
- Drift analysis, backtesting, market state
- Control plane (audit, flags, freeze)
- Merchant policy management

**Auth:** `X-API-KEY` header

---

## Database Schema (Key Tables)

| Table | Purpose |
|-------|---------|
| zones | Zone definitions (bbox + H3 indexes) |
| zone_h3_mappings | H3 R7/R8 cell → zone mappings |
| zone_vehicle_pricings | Base rates per zone × vehicle |
| zone_vehicle_time_pricings | Time-band overrides |
| zone_pair_vehicle_pricings | Corridor pricing |
| pricing_configs | City defaults per vehicle (approval workflow) |
| pricing_distance_slabs | Telescoping per-km rates |
| inter_zone_configs | Inter-zone formula weights |
| vendor_rate_cards | Vendor cost prediction rates |
| pricing_quote_decisions | Quote audit log + drift |
| pricing_backtests | Backtest results |
| pricing_outcomes | Accepted/rejected/expired tracking |
| merchant_pricing_policies | Merchant overrides |
| pricing_model_configs | Shadow model definitions |

---

## Documentation

- [Engine Design](docs/ENGINE_DESIGN.md) — Architecture and component details
- [Pricing Calculation Guide](docs/pricing-calculation-guide.md) — Detailed formula walkthrough
- [Zone Configuration](config/zones/README.md) — YAML format and sync commands
- [Pricing Backlog](docs/SWAPZEN_PRICING_BACKLOG.md) — Feature roadmap
- [Platform Plan](docs/SWAPZEN_HYPERLOCAL_PRICING_PLATFORM_PLAN.md) — Long-term vision
