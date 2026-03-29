# SwapZen Pricing Engine - How Pricing Works

## Overview

The pricing engine calculates delivery prices for SwapZen's marketplace. It takes a pickup location, drop location, vehicle type, and time of request — then returns a fair price calibrated against industry benchmarks (Porter).

The engine follows a **5-step pipeline**:

```
Request → Route Resolution → Zone Resolution (H3) → Price Calculation → Guardrail Check → Final Price
```

---

## 1. Route Resolution (Distance & Traffic)

The first step fetches the actual driving distance and traffic conditions from the Google Maps API.

**Inputs:** Pickup coordinates, Drop coordinates, City, Vehicle type

**Outputs:**
| Field | Description |
|-------|-------------|
| `distance_m` | Driving distance in meters |
| `duration_s` | Normal driving time (no traffic) |
| `duration_in_traffic_s` | Driving time with current traffic |

**Caching:** Routes are cached for **2 hours** with time-bucketed keys to prevent serving stale traffic data. The same route requested at 10 AM vs 6 PM gets fresh traffic data.

---

## 2. Zone Resolution (H3 Hexagonal Grid)

Every location falls into a **zone** — a geographic area with specific pricing characteristics. Hyderabad has 90 zones covering different area types.

### Zone Types

| Zone Type | Examples | Pricing Character |
|-----------|----------|-------------------|
| `tech_corridor` | HITEC City, Financial District | Competitive (high supply) |
| `business_cbd` | Ameerpet, Secunderabad | Premium (congestion) |
| `heritage_commercial` | Charminar, Koti | Narrow roads premium |
| `premium_residential` | Banjara Hills, Jubilee Hills | Premium |
| `airport_logistics` | Shamshabad Airport area | Long-haul premium |
| `traditional_commercial` | Old city commercial | Slight premium |
| `industrial` | Jeedimetla, Pashamylaram | Volume discount |
| `residential_dense` | LB Nagar, Dilsukhnagar | Standard |
| `residential_mixed` | Kukatpally, Miyapur | Standard |
| `residential_growth` | Kompally, Adibatla | Slight discount (grow adoption) |
| `outer_ring` | ORR-adjacent areas | Standard |

### How Zone Lookup Works (H3)

1. Convert pickup/drop coordinates to H3 R7 hex index
2. Look up zone from in-memory R7 → zone map (O(1))
3. If R7 cell is shared by multiple zones (boundary), check R8 children for disambiguation
4. Fallback to bounding box scan if H3 map not populated

**Priority ordering:** Tech corridors (20) > Business CBD/Heritage (18) > Premium residential (16) > Airport (15) > Traditional commercial (14) > Industrial (12) > Residential dense/mixed (10) > Growth (8) > Outer ring (5)

---

## 3. Pricing Resolution (Which rates to use?)

Once we know the pickup zone and drop zone, the engine resolves which pricing rates (base_fare, per_km_rate) to apply. There are **5 tiers**, checked in priority order:

### Tier 1: Corridor Pricing (Highest Priority)

For specific zone-pair routes with explicit rates. 77 zone pairs have corridor pricing for all 10 vehicles.

- **When used:** An explicit `ZonePairVehiclePricing` record exists for this from_zone → to_zone pair
- **Rates:** Pre-calibrated base_fare + per_km_rate (all multipliers bypassed)
- **Time-aware:** Different rates for morning, afternoon, evening

### Tier 2: Inter-Zone Formula

For cross-zone routes without explicit corridor pricing. Computes a weighted average of both zones' rates.

```
blended_base_fare = pickup_zone_rate × 0.6 + drop_zone_rate × 0.4
blended_per_km   = pickup_zone_rate × 0.6 + drop_zone_rate × 0.4
```

Then applies a **zone-type adjustment** from `InterZoneConfig` (9 rules):

| Pattern | Morning | Afternoon | Evening | Rationale |
|---------|---------|-----------|---------|-----------|
| Residential → Tech | 1.08 | 1.00 | 0.95 | Morning rush to offices |
| Tech → Residential | 0.95 | 1.00 | 1.08 | Evening return commute |
| Any → Airport | 1.15 | 1.10 | 1.15 | Airport premium |
| Any → Old City | 1.05 | 1.08 | 1.05 | Congestion premium |
| Industrial routes | 0.98 | 0.98 | 0.98 | Volume discount |

### Tier 3: Zone + Time Override

For same-zone routes (pickup and drop in the same zone) with time-specific rates. All 90 zones have morning/afternoon/evening rates for all 10 vehicles.

### Tier 4: Zone Override

For same-zone routes using base zone rates (when no time-specific rate exists).

### Tier 5: City Default (Fallback)

Global city-level rates from the PricingConfig table (10 records, one per vehicle type).

---

## 4. Price Calculation

### Stage A: Base Fare

```
base_fare = max(zone_base_fare, zone_min_fare)
```

The base fare is the minimum "show up" cost — covers driver travel to pickup, loading, etc.

**Typical base fares (Hyderabad):**

| Vehicle | Base Fare | What it covers |
|---------|-----------|----------------|
| Two Wheeler | ~Rs 45-60 | Biker shows up with bag |
| Scooter | ~Rs 60-80 | Scooter with cargo box |
| Mini 3W | ~Rs 100-130 | Small auto-style vehicle |
| Three Wheeler | ~Rs 200-320 | Full-size auto/tempo |
| Three Wheeler EV | ~Rs 200-320 | Electric three wheeler |
| Tata Ace | ~Rs 250-360 | Mini truck |
| Pickup 8ft | ~Rs 300-470 | 8-foot pickup truck |
| Eeco | ~Rs 400-550 | Maruti Eeco van |
| Tata 407 | ~Rs 500-600 | Medium truck |
| Canter 14ft | ~Rs 1450-1580 | 14-foot truck |

### Stage B: Chargeable Distance

```
chargeable_distance = max(0, total_distance - base_distance)
```

The first **1 km** is included in the base fare (base_distance = 1000m).

### Stage C: Distance Component (Telescoping Slabs)

The per-km charge uses **distance slabs** — different rates for different distance ranges:

**Example: Two Wheeler slabs**
| Distance Range | Rate (per km) |
|---------------|---------------|
| 0 - 3 km | Rs 3.50 |
| 3 - 10 km | Rs 8.60 |
| 10 - 25 km | Rs 11.50 |
| 25+ km | Rs 7.50 |

All 10 vehicles have 4-tier slabs. Heavy vehicles have higher per-km rates at all tiers.

### Stage D: Time Component (Per-Minute)

```
time_component = duration_s / 60 × per_min_rate_paise
```

Enabled per vehicle type via `per_min_rate_paise` (defaults to 0). Compensates drivers for time spent in traffic-heavy zones.

### Stage E: Dead-KM Charge

```
if dead_km_enabled && pickup_distance > free_pickup_radius:
  dead_km_charge = (pickup_distance - free_pickup_radius) × dead_km_per_km_rate
```

Covers driver cost of traveling to pickup location. Estimated via `H3SupplyDensity` (average pickup distance per H3 cell).

### Stage F: Distance Band Shaping

A multiplier that adjusts the distance component based on trip length category:

| Distance Band | Small Vehicles | Mid Vehicles | Heavy Vehicles |
|--------------|----------------|--------------|----------------|
| Micro (0-5 km) | 0.85x (discount) | 0.90x | 0.95x |
| Short (5-12 km) | 1.00x (baseline) | 1.00x | 1.00x |
| Medium (12-20 km) | 1.05x (premium) | 1.05x | 1.05x |
| Long (20+ km) | 1.00x (neutral) | 1.00x | 1.00x |

The multiplier applies only to the distance component, NOT the base fare.

### Stage G: Zone-Level Surcharges

| Surcharge | Description | Default |
|-----------|-------------|---------|
| **Fuel Surcharge** | % added when fuel prices spike | 0% |
| **Zone Type Multiplier** | Premium/discount by area type | 1.0x |
| **ODA Surcharge** | Extra for both pickup AND drop in remote areas | 5% |
| **Special Location Fee** | Flat fee for airports, tech parks | Rs 0 |

### Stage H: Dynamic Surge (Production Mode Only)

Three dynamic factors (all set to 1.0 in calibration mode and for time-aware zone pricing):

**Traffic Multiplier** — from Google Maps traffic ratio (capped at 1.2x)
**Time-of-Day Surge** — demand patterns by time and vehicle category
**Zone Demand Multiplier** — location-based demand factor

Combined surge capped at 2.0x.

### Stage I: Vendor Margin (Two-Sided Pricing)

```
vendor_cost = VendorPayoutCalculator.predict(vendor, city, vehicle, distance, time)
margin_paise = final_price - vendor_cost
margin_pct = margin_paise / vendor_cost × 100
```

Each quote stores vendor prediction for margin analytics.

### Stage J: Rounding

| Mode | Rounding |
|------|----------|
| Production | Nearest Rs 10 |
| Calibration | Exact (nearest paisa) |

---

## 5. Unit Economics Guardrail

After calculating the price, the engine checks profitability.

### Cost Breakdown per Order

| Cost Component | Calculation |
|---------------|-------------|
| Vendor cost | = raw_subtotal |
| Payment gateway fee | = 2% of final price |
| Support buffer | = Rs 2 per order |
| Maps API cost | = Rs 0.10 per order |
| **Total cost** | = vendor + PG fee + support + maps |

### Margin Check

If margin < 5%: bump to 5% minimum, ceil to nearest Rs 10.

---

## Vehicle Categories

All vehicles are classified into three categories that affect distance band shaping, time surge, and zone multipliers:

| Category | Vehicles | Typical Capacity |
|----------|----------|-----------------|
| **Small** | Two Wheeler, Scooter | Up to 20 kg |
| **Mid** | Mini 3W, Three Wheeler, Three Wheeler EV, Tata Ace, Pickup 8ft | 100 - 1250 kg |
| **Heavy** | Eeco, Tata 407, Canter 14ft | 1000 - 3500 kg |

---

## Time Bands

| Band | Hours | Character |
|------|-------|-----------|
| Morning | 6:00 AM - 12:00 PM | Office rush, commercial loading |
| Afternoon | 12:00 PM - 6:00 PM | Business hours, steady demand |
| Evening | 6:00 PM - 6:00 AM | Evening rush + night (low supply premium) |

All time calculations use the **city's local timezone** (Asia/Kolkata for Hyderabad).

---

## Calibration

The engine is calibrated against **Porter** (India's leading intra-city logistics platform):

- **10 routes** across Hyderabad (micro to long-haul)
- **3 time bands** (morning, afternoon, evening)
- **7 vehicle types** (calibrated subset)
- **= 210 test scenarios**

**Tolerance:** -3% to +16% vs Porter prices
**Current status:** 210/210 scenarios passing (100%)

---

## Key Design Decisions

1. **H3 hexagonal grid for zone boundaries** — Replaces bounding boxes with precise hex-cell coverage. O(1) zone lookup via in-memory H3 map. Single source of truth in `h3_zones.yml`.

2. **YAML-driven configuration** — Zone rates, slabs, and adjustments are in YAML files. Easy to add new cities or tweak rates without code changes.

3. **Telescoping distance slabs** — Per-km rates vary by distance range (not a flat rate). Middle ranges cost more (operational sweet spot), very short and very long trips are cheaper per km.

4. **Time-aware zone pricing bypasses surge** — When we have explicit morning/afternoon/evening rates, dynamic surge is set to 1.0 to prevent double-counting.

5. **Distance band shaping on distance only, not base fare** — The base fare is a fixed cost (driver showing up). Only the variable distance component is shaped.

6. **Two-sided pricing** — Every quote predicts vendor cost and tracks margin. Enables margin analytics and drift detection.

7. **2-hour cache windows** — Route data (especially traffic) is cached in 2-hour buckets. Balances API costs against data freshness.
