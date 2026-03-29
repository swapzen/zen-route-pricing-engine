# Zen Route Pricing Engine - Design Document

## Overview

The Zen Route Pricing Engine is a zone-based dynamic pricing system for SwapZen's hyperlocal delivery marketplace, calibrated against Porter benchmarks. It uses H3 hexagonal grids for zone boundaries, a 5-tier pricing resolution hierarchy, and YAML-driven configuration.

---

## Architecture

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           QUOTE REQUEST                                      │
│  city_code, vehicle_type, pickup_lat/lng, drop_lat/lng, quote_time          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ZONE RESOLUTION (H3)                                 │
│  1. H3 R7 hex lookup (O(1) from in-memory map)                             │
│  2. R8 boundary disambiguation (if cell shared by zones)                    │
│  3. Bbox fallback (for staging/gaps)                                        │
│  4. Determine zone types (tech_corridor, residential, etc.)                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PRICING RESOLUTION (5-tier)                            │
│  1. Corridor Override (explicit zone-pair pricing)                          │
│  2. Inter-Zone Formula (weighted average 60/40)                             │
│  3. Zone-Time Override (intra-zone with time band)                         │
│  4. Zone Override (intra-zone base rates)                                   │
│  5. City Default (global fallback from PricingConfig)                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PRICE CALCULATION                                      │
│  base_fare                                                                  │
│  + distance_component (telescoping slabs)                                   │
│  + time_component (per-minute rate × duration)                              │
│  + dead_km_charge (pickup distance beyond free radius)                      │
│  × distance_band_multiplier                                                 │
│  × traffic_multiplier                                                       │
│  + vendor_predicted_paise (two-sided margin)                                │
│  = final_price (rounded to Rs 10)                                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Zone System (H3 Hexagonal Grid)

### Zone Boundaries

All 90 Hyderabad zones are defined by H3 R7 hexagonal cells (~5.16 km2 each). The `h3_zones.yml` file is the single source of truth.

**Resolution levels:**
- R7 (~5.16 km2): Primary zone mapping. Each zone owns a set of R7 cells.
- R8 (~0.74 km2): Boundary disambiguation. When an R7 cell is shared by zones, R8 children resolve the exact zone.

### Zone Types

| Type | Description | Default Multiplier | Priority |
|------|-------------|--------------------|----------|
| `tech_corridor` | IT parks, tech hubs | 1.00 | 20 |
| `business_cbd` | Central business districts | 1.05 | 18 |
| `heritage_commercial` | Old city commercial | 1.02 | 18 |
| `premium_residential` | High-end areas | 1.15 | 16 |
| `airport_logistics` | Airport and logistics | 1.10 | 15 |
| `traditional_commercial` | Traditional commercial | 1.02 | 14 |
| `industrial` | Industrial zones | 0.95 | 12 |
| `residential_dense` | Dense residential | 1.00 | 10 |
| `residential_mixed` | Mixed-use residential | 1.00 | 10 |
| `residential_growth` | Growth corridors | 0.95 | 8 |
| `outer_ring` | ORR-adjacent areas | 1.00 | 5 |
| `default` | Default | 1.00 | 10 |

### H3 Zone Resolution

```ruby
# O(1) lookup — convert lat/lng → H3 R7 hex → zone
h3_resolver = H3ZoneResolver.for_city('hyd')
zone = h3_resolver.resolve(lat, lng)
# Falls through: R7 map → R8 boundary → bbox fallback
```

### Zone Coverage (Hyderabad)

- 90 total zones (76 manual + 14 auto-generated)
- ~740 H3 R7 cells
- 77 zones with corridor pricing
- All 90 zones have 10-vehicle × 3-band pricing

---

## Pricing Resolution

### Tier 1: Corridor Override (Highest Priority)

Explicit pricing for specific zone pairs. 77 zone pairs have corridor pricing covering all 10 vehicles × 3 time bands.

```yaml
hitech_to_fin_district:
  from_zone: hitech_madhapur
  to_zone: fin_district
  directional: false
  pricing:
    morning:
      two_wheeler: { base: 4600, rate: 670 }
      three_wheeler: { base: 16700, rate: 3000 }
      # ... all 10 vehicles
```

### Tier 2: Inter-Zone Formula

For cross-zone routes without corridors:

```
base_fare = (pickup_zone.base × 0.6) + (drop_zone.base × 0.4)
per_km_rate = (pickup_zone.rate × 0.6) + (drop_zone.rate × 0.4)
```

With zone-type adjustments from `InterZoneConfig`:

| Pattern | Morning | Afternoon | Evening |
|---------|---------|-----------|---------|
| Residential → Tech | +5-8% | +0% | -5% |
| Tech → Residential | -5% | +0% | +5-8% |
| Any → Old City | +5% | +8% | +5% |
| Airport routes | +10-15% | +5-10% | +10-15% |

### Tier 3: Zone-Time Override

Time-band-specific rates within a zone (morning/afternoon/evening).

### Tier 4: Zone Override

Base zone rates (morning rates used as base).

### Tier 5: City Default (Fallback)

Global rates from `PricingConfig` table (10 records, one per vehicle type).

---

## Distance Slabs

Telescoping per-km rates that vary by distance range. Configured per vehicle in `vehicle_defaults.yml` and synced to `PricingDistanceSlab` table.

Example (two_wheeler):

| Distance Range | Rate (paise/km) |
|---------------|-----------------|
| 0 - 3,000m | 350 |
| 3,000 - 10,000m | 860 |
| 10,000 - 25,000m | 1150 |
| 25,000m+ | 750 |

40 total slabs (4 tiers × 10 vehicles).

---

## Vehicle Categories

| Category | Vehicles | Code Values |
|----------|----------|-------------|
| **SMALL** | Two Wheeler, Scooter | `two_wheeler`, `scooter` |
| **MID** | Mini 3W, Three Wheeler, Three Wheeler EV, Tata Ace, Pickup 8ft | `mini_3w`, `three_wheeler`, `three_wheeler_ev`, `tata_ace`, `pickup_8ft` |
| **HEAVY** | Eeco, Tata 407, Canter 14ft | `eeco`, `tata_407`, `canter_14ft` |

All 10 vehicle types defined in `app/services/route_pricing/vehicle_categories.rb`.

---

## Two-Sided Pricing (Vendor Rate Card)

The engine predicts vendor cost per quote using `VendorPayoutCalculator`:
- Vendor rate cards stored in `vendor_rate_cards` table (synced from `config/vendors/*.yml`)
- Each quote includes: `vendor_predicted_paise`, `margin_paise`, `margin_pct`, `vendor_confidence`
- `PricingActual` auto-computes `prediction_variance` on create

---

## Per-Minute Pricing + Dead-KM

- `per_min_rate_paise` on pricing tables (defaults to 0 — enable per vehicle)
- `dead_km_enabled`, `free_pickup_radius_m`, `dead_km_per_km_rate_paise` on PricingConfig
- `H3SupplyDensity` table for per-cell pickup distance estimates
- `time_component` and `dead_km_charge` in PriceCalculator breakdown

---

## Operational Infrastructure

### Approval Workflow (P0)
- `approval_status` on pricing_configs: draft → pending → approved → rejected
- Maker-checker pattern in configs_controller

### Drift Detection (P0)
- Drift columns on `pricing_quote_decisions`
- `DriftAnalyzer` service computes quote vs actual variance
- Auto-logged on `PricingActual` create

### Backtesting (P0)
- `pricing_backtests` table stores replay results
- `BacktestRunner` replays historical quotes against candidate configs

### Control Plane (P1)
- `pricing_change_logs` — audit trail for all changes
- `pricing_rollout_flags` — feature gates by city/vehicle
- `pricing_emergency_freezes` — city-level freeze switch

### Market State (P1)
- `pricing_outcomes` — accepted/rejected/expired tracking
- `MarketStateAggregator` — pressure map by zone/vehicle/time

### Merchant Policies (P1)
- `merchant_pricing_policies` — floor/cap/markup/discount/fixed_rate per merchant
- QuoteEngine accepts `merchant_id` to apply policies

### Shadow Model (P2)
- `pricing_model_configs` + `pricing_model_scores` tables
- `CandidatePriceOptimizer` shadow-scores every quote
- Compare model suggestions with live decisions

---

## Configuration Files

### Source of Truth

```
config/zones/hyderabad/h3_zones.yml     # All 90 zones + H3 cells + pricing
config/zones/hyderabad/vehicle_defaults.yml  # Global rates, slabs, inter-zone formula
config/vendors/porter_enterprise.yml     # Vendor rate cards
```

### Legacy (still functional, superseded by h3_zones.yml)

```
config/zones/hyderabad.yml              # Bbox zone definitions (76 manual zones)
config/zones/hyderabad/pricing/*.yml    # Per-zone pricing (6 zones)
```

### Sync Flow

```
h3_zones.yml (version controlled, source of truth)
        │
        ▼
    zones:h3_sync rake task (H3ZoneConfigLoader)
        │
        ├── Zones (create/update with auto-computed bbox)
        ├── H3 mappings (ZoneH3Mapping per R7 cell)
        ├── Zone pricing (10 vehicles × 3 bands per zone)
        ├── PricingConfig city defaults (10 records)
        ├── PricingDistanceSlab (40 records)
        ├── InterZoneConfig (1 record + 9 adjustments)
        └── H3ZoneResolver cache rebuild
        │
        ▼
    Database Tables (runtime)
        │
        ▼
    Admin UI can edit (changes persist until next sync)
```

---

## Calibration

### Porter Benchmark

- **10 test routes** covering different zone types and distances
- **3 time bands** (morning, afternoon, evening)
- **7 vehicle types** (calibrated subset)
- **210 total scenarios**
- **Tolerance:** -3% to +16% vs Porter prices

### Current Status

**100% Pass Rate** (210/210 scenarios)

---

## Key Components

### H3ZoneConfigLoader

Reads h3_zones.yml and syncs everything to DB:

```ruby
H3ZoneConfigLoader.new('hyd').sync!                    # Normal sync
H3ZoneConfigLoader.new('hyd').sync!(force_pricing: true)  # Force overwrite
```

### H3ZoneResolver

O(1) zone lookup via H3 hexagonal grid:

```ruby
resolver = RoutePricing::Services::H3ZoneResolver.for_city('hyd')
zone = resolver.resolve(17.45, 78.38)
```

### ZonePricingResolver

5-tier pricing resolution:

```ruby
resolver = RoutePricing::Services::ZonePricingResolver.new
result = resolver.resolve(
  city_code: 'hyd', vehicle_type: 'two_wheeler',
  pickup_lat: 17.45, pickup_lng: 78.38,
  drop_lat: 17.43, drop_lng: 78.35,
  time_band: 'morning'
)
```

### PriceCalculator

Full price calculation with all components:

```ruby
calculator = RoutePricing::Services::PriceCalculator.new(config, distance_m, vehicle_type)
result = calculator.calculate
# => { final_price_paise: 14000, breakdown: { base_fare, distance_component, time_component, dead_km_charge, ... } }
```

---

## References

- [Pricing Calculation Guide](pricing-calculation-guide.md) - Detailed formula documentation
- [Zone Config README](../config/zones/README.md) - YAML format guide
- [Pricing Backlog](SWAPZEN_PRICING_BACKLOG.md) - Feature roadmap
- [Platform Plan](SWAPZEN_HYPERLOCAL_PRICING_PLATFORM_PLAN.md) - Long-term vision
