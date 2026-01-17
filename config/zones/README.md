# Zone Configuration Guide

This directory contains YAML-based zone and pricing configurations for the Zen Route Pricing Engine.

## Directory Structure

```
config/zones/
├── hyderabad.yml              # Main zone definitions (71 zones)
└── hyderabad/
    ├── vehicle_defaults.yml   # Global vehicle configs & inter-zone formula
    ├── pricing/               # Zone-specific pricing
    │   ├── fin_district.yml
    │   ├── hitech_madhapur.yml
    │   └── ...
    └── corridors/
        └── priority_corridors.yml  # High-traffic corridor pricing
```

## Main Zone File Format

`hyderabad.yml`:

```yaml
city_code: hyd
city_name: Hyderabad
version: "1.0"

zones:
  hitech_madhapur:
    name: "HITEC City & Madhapur Hub"
    zone_type: tech_corridor
    active: true
    bounds:
      lat_min: 17.43
      lat_max: 17.455
      lng_min: 78.37
      lng_max: 78.41
    multipliers:
      small_vehicle: 1.0
      mid_truck: 1.0
      heavy_truck: 1.0
      default: 1.0
```

## Zone Pricing Format

`pricing/fin_district.yml`:

```yaml
zone_code: fin_district
zone_type: tech_corridor

pricing:
  morning:
    two_wheeler:   { base: 5000, rate: 2000 }
    scooter:       { base: 7000, rate: 2600 }
    three_wheeler: { base: 25000, rate: 8000 }
  afternoon:
    two_wheeler:   { base: 4800, rate: 2350 }
    # ...
  evening:
    two_wheeler:   { base: 4300, rate: 2150 }
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
    description: "JNTU → HITEC City (Morning IT Commute)"
    pricing:
      morning:
        two_wheeler: { base: 4500, rate: 700 }
        # ...
```

## Commands

```bash
# Sync all configs to database
rails zones:sync city=hyd

# Force overwrite (reset to YAML)
rails zones:sync city=hyd force=true

# Preview changes (dry run)
rails zones:sync city=hyd dry=true

# List zones
rails zones:list city=hyd

# Show stats
rails zones:pricing city=hyd
rails zones:corridors city=hyd
```

## Adding a New Zone

1. Add zone definition to `hyderabad.yml`
2. (Optional) Add zone-specific pricing in `pricing/{zone_code}.yml`
3. (Optional) Add corridors in `corridors/priority_corridors.yml`
4. Run `rails zones:sync city=hyd`

## Editing Existing Pricing

### Via YAML (recommended for bulk changes)
1. Edit the YAML file
2. Run `rails zones:sync city=hyd force=true`

### Via Admin UI (for live tweaks)
1. Edit in Admin dashboard
2. Changes persist until next `force=true` sync
