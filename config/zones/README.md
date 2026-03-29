# Zone Configuration Guide

This directory contains YAML-based zone and pricing configurations for the Zen Route Pricing Engine.

## Directory Structure

```
config/zones/
├── hyderabad.yml                  # Legacy bbox zone definitions (76 manual zones)
└── hyderabad/
    ├── h3_zones.yml               # H3 zone definitions + pricing (SOURCE OF TRUTH)
    ├── vehicle_defaults.yml       # Global vehicle configs, slabs, inter-zone formula
    ├── hyderabad_auto_zone.yml    # Auto-zone generation config
    ├── pricing/                   # Legacy per-zone pricing (6 zones)
    │   ├── fin_district.yml
    │   ├── hitech_madhapur.yml
    │   └── ...
    └── corridors/                 # Corridor pricing (77 zone pairs)
        ├── priority_corridors.yml
        ├── route_4_fin_to_ameerpet.yml
        └── route_matrix_8band.yml
```

## Source of Truth: h3_zones.yml

The `h3_zones.yml` file defines ALL zones with their H3 hex cells and pricing. This is the primary config file.

**Format:**

```yaml
city_code: hyd
version: "1.0"
generated_at: "2026-03-29T..."

zones:
  fin_district:
    name: "Financial District"
    zone_type: tech_corridor
    priority: 20
    active: true
    auto_generated: false
    h3_cells_r7:
      - "872a1070bffffff"
      - "872a1070affffff"
    pricing:
      morning:
        two_wheeler: { base: 4000, rate: 800 }
        scooter: { base: 7700, rate: 900 }
        mini_3w: { base: 14600, rate: 900 }
        three_wheeler: { base: 31800, rate: 2100 }
        three_wheeler_ev: { base: 31800, rate: 2100 }
        tata_ace: { base: 35500, rate: 2200 }
        pickup_8ft: { base: 47300, rate: 2000 }
        eeco: { base: 55000, rate: 3800 }
        tata_407: { base: 60000, rate: 4200 }
        canter_14ft: { base: 163400, rate: 3900 }
      afternoon:
        # ... all 10 vehicles
      evening:
        # ... all 10 vehicles
```

## Vehicle Defaults Format

`vehicle_defaults.yml` contains global rates, distance slabs, and inter-zone formula:

```yaml
vehicles:
  two_wheeler:
    base_fare_paise: 5000
    slabs:
      - [0, 3000, 350]       # 0-3km: 350 paise/km
      - [3000, 10000, 860]   # 3-10km: 860 paise/km
      - [10000, 25000, 1150] # 10-25km: 1150 paise/km
      - [25000, null, 750]   # 25km+: 750 paise/km

global_time_rates:
  morning:
    two_wheeler: { base: 4000, rate: 800 }
    # ... all 10 vehicles
  afternoon:
    # ...
  evening:
    # ...

inter_zone_formula:
  origin_weight: 0.6
  destination_weight: 0.4
  type_adjustments:
    residential_to_tech:
      morning: 1.08
      afternoon: 1.0
      evening: 0.95
    # ...
```

## Corridor Pricing Format

`corridors/priority_corridors.yml`:

```yaml
morning_rush_corridors:
  jntu_to_hitech:
    from_zone: jntu_kukatpally
    to_zone: hitech_madhapur
    directional: true
    description: "JNTU -> HITEC City (Morning IT Commute)"
    pricing:
      morning:
        two_wheeler: { base: 4500, rate: 700 }
        # ... all 10 vehicles
```

## Commands

### Primary (H3-based)

```bash
# Export DB zones → h3_zones.yml (generate/update the source of truth)
rails zones:h3_export[hyd]

# Sync h3_zones.yml → DB (zones, H3 mappings, pricing, configs, slabs, inter-zone)
rails zones:h3_sync[hyd]

# Force overwrite existing pricing
FORCE_PRICING=true rails zones:h3_sync[hyd]
```

### Legacy

```bash
# Sync from legacy YAML files (hyderabad.yml + pricing/*.yml + corridors/*.yml)
rails zones:sync city=hyd

# Force overwrite
rails zones:sync city=hyd force=true
```

### Inspection

```bash
rails zones:list city=hyd       # List all zones
rails zones:pricing city=hyd    # Show pricing stats
rails zones:corridors city=hyd  # Show corridor stats
```

## Adding a New Zone

1. Export current state: `rails zones:h3_export[hyd]`
2. Edit `h3_zones.yml` — add zone with H3 cells + pricing
3. Sync to DB: `rails zones:h3_sync[hyd]`

## Editing Pricing

### Via YAML (recommended for bulk changes)
1. Edit `h3_zones.yml`
2. Run `FORCE_PRICING=true rails zones:h3_sync[hyd]`

### Via Admin UI (for live tweaks)
1. Edit in Admin dashboard (swapzen-admin)
2. Changes persist until next `FORCE_PRICING=true` sync

## Zone Types

| Type | Multiplier | Description |
|------|-----------|-------------|
| tech_corridor | 1.00 | IT parks, tech hubs |
| business_cbd | 1.05 | Central business districts |
| heritage_commercial | 1.02 | Old city commercial areas |
| premium_residential | 1.15 | High-end residential |
| airport_logistics | 1.10 | Airport and logistics |
| traditional_commercial | 1.02 | Traditional commercial |
| industrial | 0.95 | Industrial zones |
| residential_dense | 1.00 | Dense residential |
| residential_mixed | 1.00 | Mixed-use residential |
| residential_growth | 0.95 | Growth corridors |
| outer_ring | 1.00 | ORR-adjacent areas |
| default | 1.00 | Default |
