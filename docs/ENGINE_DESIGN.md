# Zen Route Pricing Engine - Design Document

## Overview

The Zen Route Pricing Engine is a zone-based dynamic pricing system designed to compete with Porter and other logistics providers in the Indian market. It uses a tiered pricing resolution system with YAML-driven configuration for easy management and version control.

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
│                         ZONE RESOLUTION                                      │
│  1. Find pickup zone (bbox lookup)                                          │
│  2. Find drop zone (bbox lookup)                                            │
│  3. Determine zone types (tech_corridor, residential, etc.)                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PRICING RESOLUTION                                     │
│  Priority order:                                                            │
│  1. Corridor Override (explicit zone-pair pricing)                          │
│  2. Inter-Zone Formula (weighted average)                                   │
│  3. Zone-Time Override (intra-zone with time band)                         │
│  4. City Default (global fallback)                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PRICE CALCULATION                                      │
│  base_fare + (chargeable_distance × per_km_rate)                           │
│  × distance_band_multiplier                                                 │
│  × traffic_multiplier                                                       │
│  + variance_buffer                                                          │
│  = final_price (rounded to ₹10)                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Zone System

### Zone Definition

Each zone is defined with:
- **zone_code**: Unique identifier (e.g., `hitech_madhapur`)
- **zone_type**: Category for pricing behavior
- **bounds**: Bounding box (lat_min, lat_max, lng_min, lng_max)
- **active**: Whether zone is operational

### Zone Types

| Type | Description | Default Multiplier |
|------|-------------|-------------------|
| `tech_corridor` | IT parks, tech hubs (HITEC City, Gachibowli) | 1.00 |
| `business_cbd` | Central business districts (Ameerpet, Secunderabad) | 1.05 |
| `airport_logistics` | Airport and logistics (Shamshabad) | 1.10 |
| `residential_dense` | Dense residential (LB Nagar, Dilsukhnagar) | 1.00 |
| `residential_mixed` | Mixed-use (Kukatpally, Miyapur) | 1.00 |
| `residential_growth` | Growth corridors (Uppal, Kompally) | 0.95 |
| `traditional_commercial` | Old city (Charminar, Koti) | 1.02 |
| `premium_residential` | High-end (Banjara Hills, Jubilee Hills) | 1.15 |
| `industrial` | Industrial zones (Patancheru, Jeedimetla) | 0.95 |

---

## Pricing Resolution

### 1. Corridor Override (Highest Priority)

Explicit pricing for specific zone pairs. Used for:
- High-traffic routes (morning rush to tech hubs)
- Competitive routes (where Porter is aggressive)
- Routes requiring precise calibration

```yaml
# Example corridor
hitech_to_fin_district:
  from_zone: hitech_madhapur
  to_zone: fin_district
  directional: false
  pricing:
    morning:
      two_wheeler: { base: 4600, rate: 670 }
      three_wheeler: { base: 16700, rate: 3000 }
```

### 2. Inter-Zone Formula

For zone pairs without explicit corridors, pricing is calculated algorithmically:

```
base_fare = (pickup_zone.base × 0.6) + (drop_zone.base × 0.4)
per_km_rate = (pickup_zone.rate × 0.6) + (drop_zone.rate × 0.4)
```

With zone-type adjustments:

| Pattern | Morning | Afternoon | Evening |
|---------|---------|-----------|---------|
| Residential → Tech | +5-8% | +0% | -5% |
| Tech → Residential | -5% | +0% | +5-8% |
| Any → Old City | +5% | +8% | +5% |
| Airport routes | +10-15% | +5-10% | +10-15% |

### 3. Zone-Time Override

Intra-zone pricing with time-band variations:

```yaml
fin_district:
  zone_type: tech_corridor
  pricing:
    morning:
      two_wheeler: { base: 5000, rate: 2000 }
    afternoon:
      two_wheeler: { base: 4800, rate: 2350 }
    evening:
      two_wheeler: { base: 4300, rate: 2150 }
```

### 4. City Default

Fallback to global PricingConfig when no zone-specific pricing exists.

---

## Distance Bands

Multipliers based on trip distance:

| Band | Distance | Multiplier |
|------|----------|------------|
| Micro | 0-3 km | 0.85 |
| Short | 3-10 km | 1.00 |
| Medium | 10-25 km | 1.00 |
| Long | 25+ km | 0.82 |

---

## Configuration Files

### Directory Structure

```
config/zones/
├── hyderabad.yml              # Zone boundaries
└── hyderabad/
    ├── vehicle_defaults.yml   # Global rates, inter-zone formula config
    ├── pricing/               # Zone-specific rates
    │   ├── fin_district.yml
    │   ├── hitech_madhapur.yml
    │   ├── lb_nagar_east.yml
    │   ├── ameerpet_core.yml
    │   ├── old_city.yml
    │   ├── jntu_kukatpally.yml
    │   ├── vanasthali.yml
    │   └── ayyappa_society.yml
    └── corridors/
        └── priority_corridors.yml
```

### Sync Flow

```
YAML Files (version controlled)
        │
        ▼
    zones:sync rake task
        │
        ▼
Database Tables (runtime)
        │
        ▼
    Admin UI can edit
        │
        ▼
   zones:sync force=true (reset to YAML)
```

---

## Calibration

### Porter Benchmark

The engine is calibrated against Porter's pricing with:
- **10 test routes** covering different zone types
- **3 time bands** (morning, afternoon, evening)
- **7 vehicle types**
- **210 total scenarios**

### Acceptance Criteria

- Variance must be between **-3%** and **+16%** of Porter
- Negative variance (underpricing) is limited to protect margins
- Positive variance allows competitive buffer

### Current Status

**100% Pass Rate** ✅

---

## Key Components

### ZonePricingResolver

Determines the pricing source and rates for a given route:

```ruby
resolver = RoutePricing::Services::ZonePricingResolver.new
result = resolver.resolve(
  city_code: 'hyd',
  vehicle_type: 'two_wheeler',
  pickup_lat: 17.45,
  pickup_lng: 78.38,
  drop_lat: 17.43,
  drop_lng: 78.35,
  time_band: 'morning'
)
# => Result(source: :corridor_override, base_fare_paise: 4600, ...)
```

### ZoneConfigLoader

Syncs YAML configuration to database:

```ruby
loader = ZoneConfigLoader.new('hyd')
loader.sync!(force_pricing: false)  # Preserves admin edits
loader.sync!(force_pricing: true)   # Overwrites with YAML
```

### PriceCalculator

Calculates final price with all multipliers:

```ruby
calculator = RoutePricing::Services::PriceCalculator.new(
  config,      # from ZonePricingResolver
  distance_m,  # from Google Maps
  vehicle_type
)
result = calculator.calculate
# => { final_price_paise: 14000, breakdown: {...} }
```

---

## Future Enhancements

1. **Polygon Zones** - Replace bbox with precise polygon boundaries
2. **ML-based Pricing** - Dynamic rate optimization
3. **Multi-city Support** - Bangalore, Mumbai, Delhi
4. **Real-time Traffic** - Live traffic-based surge
5. **Demand Forecasting** - Predictive pricing adjustments

---

## References

- [README.md](../README.md) - Quick start guide
- [Zone Config README](../config/zones/README.md) - YAML format guide
- [API Spec](openapi.json) - OpenAPI specification
