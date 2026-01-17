# Zen Route Pricing Engine

**Production-grade microservice for hyper-local delivery pricing.**

Calculates competitive delivery costs for SwapZen's marketplace, ensuring profitability through conservative buffers, dynamic surge pricing, and traffic-aware routing.

---

## 🚀 Quick Start

### Prerequisites
- Ruby 3.3.6+
- Rails 8.0+
- CockroachDB (Postgres-compatible)
- Redis (for route caching)
- Google Maps API Key (production)

### Setup

```bash
# 1. Install dependencies
bundle install

# 2. Configure environment variables
cp .env.example .env
nano .env  # Add your actual keys

# 3. Configure database (shared with swapzen-api)
# Edit .env: DATABASE_URL=postgresql://root@localhost:26257/swapzen_development

# 4. Run migrations (if not already run)
rails db:migrate

# 5. Sync zone configurations from YAML
rails zones:sync city=hyd

# 6. Start server
rails server -p 3001
```

**See [ENV_SETUP.md](ENV_SETUP.md) for detailed environment variable configuration.**

---

## 🗺️ Zone-Based Pricing System

### Architecture Overview

The pricing engine uses a **YAML-driven zone configuration** system:

```
config/zones/
├── hyderabad.yml              # Zone boundaries (71 zones)
└── hyderabad/
    ├── vehicle_defaults.yml   # Global vehicle configs
    ├── pricing/               # Zone-specific rates
    │   ├── fin_district.yml
    │   ├── hitech_madhapur.yml
    │   └── ... (8 zones)
    └── corridors/
        └── priority_corridors.yml  # 25+ high-traffic corridors
```

### Pricing Resolution Hierarchy

1. **Corridor Override** - Explicit zone-pair pricing (highest priority)
2. **Inter-Zone Formula** - Weighted average of origin/destination zones
3. **Zone-Time Override** - Zone-specific time-band rates
4. **City Default** - Fallback global rates

### Zone Management Commands

```bash
# Sync zones, pricing & corridors from YAML to database
rails zones:sync city=hyd

# Force overwrite existing pricing (reset to YAML values)
rails zones:sync city=hyd force=true

# List all zones
rails zones:list city=hyd

# Show pricing stats
rails zones:pricing city=hyd

# Show corridor stats
rails zones:corridors city=hyd

# Test a specific route
rails zones:test_route city=hyd plat=17.4 plng=78.4 dlat=17.5 dlng=78.5 vehicle=two_wheeler time=morning
```

### Zone Types

| Type | Description | Multiplier |
|------|-------------|------------|
| tech_corridor | IT parks, tech hubs | 1.00 |
| business_cbd | Central business districts | 1.05 |
| airport_logistics | Airport and logistics | 1.10 |
| residential_dense | Dense residential | 1.00 |
| residential_mixed | Mixed-use residential | 1.00 |
| residential_growth | Growth corridors | 0.95 |
| traditional_commercial | Old city commercial | 1.02 |
| premium_residential | High-end areas | 1.15 |
| industrial | Industrial zones | 0.95 |

---

## 🧪 Testing

### Porter Benchmark Test

```bash
# Run comprehensive pricing test (210 scenarios)
PRICING_MODE=calibration bundle exec ruby script/test_pricing_engine.rb
```

**Current Status: 100% Pass Rate** ✅

---

## 🏗️ Architecture

### Pricing Algorithm

1. Resolve Zones (pickup & drop)
2. Check Corridor Override (zone pair pricing)
3. Or Inter-Zone Formula (weighted avg)
4. Or Zone-Time Override (intra-zone)
5. Calculate: base_fare + (chargeable_km × per_km_rate)
6. Apply distance band multiplier
7. Apply traffic/surge multipliers
8. Add variance buffer (5-8%)
9. Apply margin guardrail (min 3-4%)
10. Round to nearest ₹10

### Inter-Zone Formula

For zone pairs without corridors:
- base = (pickup_zone.base × 0.6) + (drop_zone.base × 0.4)
- rate = (pickup_zone.rate × 0.6) + (drop_zone.rate × 0.4)

With zone-type adjustments for commute patterns.

---

## 📊 Database Schema

- zones - Geographic zone definitions
- zone_vehicle_pricings - Zone-specific base rates
- zone_vehicle_time_pricings - Time-band variations
- zone_pair_vehicle_pricings - Corridor pricing
- pricing_configs - Global vehicle configs

---

## 📚 Documentation

- [Engine Design](docs/ENGINE_DESIGN.md)
- [Zone Configuration](config/zones/README.md)
- [API Spec](docs/openapi.json)
