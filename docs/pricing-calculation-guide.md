# SwapZen Pricing Engine - How Pricing Works

## Overview

The pricing engine calculates delivery prices for SwapZen's marketplace. It takes a pickup location, drop location, vehicle type, and time of request - then returns a fair price calibrated against industry benchmarks (Porter).

The engine follows a **5-step pipeline**:

```
Request → Route Resolution → Zone Resolution → Price Calculation → Guardrail Check → Final Price
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

## 2. Zone Resolution (Where are pickup & drop?)

Every location falls into a **zone** - a geographic area with specific pricing characteristics. Hyderabad has 55 zones covering different area types.

### Zone Types

| Zone Type | Examples | Pricing Character |
|-----------|----------|-------------------|
| `tech_corridor` | HITEC City, Financial District | Competitive (high supply) |
| `business_cbd` | Banjara Hills, Jubilee Hills | Premium (congestion) |
| `airport_logistics` | Shamshabad Airport area | Long-haul premium |
| `residential_dense` | Ameerpet, Kukatpally | Standard |
| `residential_growth` | Kompally, Adibatla | Slight discount (grow adoption) |
| `premium_residential` | Jubilee Hills core | Premium |
| `traditional_commercial` | Charminar, Koti | Slight premium (narrow roads) |
| `industrial` | Jeedimetla, Pashamylaram | Volume discount |
| `outer_ring` | ORR-adjacent areas | Standard |

### How Zone Lookup Works

1. Load all active zones for the city, sorted by **priority** (specific zones first) and **zone_code** (for deterministic tie-breaking)
2. Check if the coordinate falls inside each zone's bounding box
3. First match wins (higher priority = more specific zone)

**Priority ordering:** Tech corridors (20) > Business CBD (18) > Premium residential (16) > Airport (15) > ... > Outer ring (5)

---

## 3. Pricing Resolution (Which rates to use?)

Once we know the pickup zone and drop zone, the engine resolves which pricing rates (base_fare, per_km_rate) to apply. There are **5 tiers**, checked in priority order:

### Tier 1: Corridor Pricing (Highest Priority)

For specific zone-pair routes with explicit rates. Example: Financial District → Ameerpet has its own calibrated rates for each vehicle type and time band.

- **When used:** An explicit `ZonePairVehiclePricing` record exists for this from_zone → to_zone pair
- **Rates:** Pre-calibrated base_fare + per_km_rate (all multipliers bypassed)
- **Time-aware:** Different rates for morning, afternoon, evening

### Tier 2: Inter-Zone Formula

For cross-zone routes without explicit corridor pricing. Computes a weighted average of both zones' rates.

```
blended_base_fare = pickup_zone_rate × 0.6 + drop_zone_rate × 0.4
blended_per_km   = pickup_zone_rate × 0.6 + drop_zone_rate × 0.4
```

Then applies a **zone-type adjustment** based on commute patterns:

| Pattern | Morning | Afternoon | Evening | Rationale |
|---------|---------|-----------|---------|-----------|
| Residential → Tech | 1.08 | 1.00 | 0.95 | Morning rush to offices |
| Tech → Residential | 0.95 | 1.00 | 1.08 | Evening return commute |
| Any → Airport | 1.15 | 1.10 | 1.15 | Airport premium |
| Any → Old City | 1.05 | 1.08 | 1.05 | Congestion premium |
| Industrial routes | 0.98 | 0.98 | 0.98 | Volume discount |

### Tier 3: Zone + Time Override

For same-zone routes (pickup and drop in the same zone) with time-specific rates. Example: Within HITEC City, morning rates differ from evening rates.

### Tier 4: Zone Override

For same-zone routes using base zone rates (when no time-specific rate exists).

### Tier 5: City Default (Fallback)

Global city-level rates from the PricingConfig table. Used when no zone-specific pricing exists.

---

## 4. Price Calculation

This is the core formula. The calculation has multiple stages:

### Stage A: Base Fare

```
base_fare = max(zone_base_fare, zone_min_fare)
```

The base fare is the minimum "show up" cost - covers driver travel to pickup, loading, etc.

**Typical base fares (Hyderabad):**

| Vehicle | Base Fare | What it covers |
|---------|-----------|----------------|
| Two Wheeler | ~Rs 45-60 | Biker shows up with bag |
| Scooter | ~Rs 60-80 | Scooter with cargo box |
| Mini 3W | ~Rs 100-130 | Small auto-style vehicle |
| Three Wheeler | ~Rs 200-320 | Full-size auto/tempo |
| Tata Ace | ~Rs 250-360 | Mini truck |
| Pickup 8ft | ~Rs 300-470 | 8-foot pickup truck |
| Canter 14ft | ~Rs 1450-1580 | 14-foot truck |

### Stage B: Chargeable Distance

```
chargeable_distance = max(0, total_distance - base_distance)
```

The first **1 km** is included in the base fare (base_distance = 1000m). You only pay per-km rates after that.

### Stage C: Distance Component

The per-km charge uses **distance slabs** - different rates for different distance ranges:

**Example: Two Wheeler slabs**
| Distance Range | Rate (per km) |
|---------------|---------------|
| 0 - 3 km | Rs 3.50 |
| 3 - 10 km | Rs 8.60 |
| 10 - 25 km | Rs 11.50 |
| 25+ km | Rs 7.50 |

The middle ranges cost more per km (sweet spot for operations), while very short and very long trips are cheaper per km.

### Stage D: Distance Band Shaping

A multiplier that adjusts the distance component based on trip length category:

| Distance Band | Small Vehicles | Mid Vehicles | Heavy Vehicles |
|--------------|----------------|--------------|----------------|
| Micro (0-5 km) | 0.85x (discount) | 0.90x | 0.95x |
| Short (5-12 km) | 1.00x (baseline) | 1.00x | 1.00x |
| Medium (12-20 km) | 1.05x (premium) | 1.05x | 1.05x |
| Long (20+ km) | 1.00x (neutral) | 1.00x | 1.00x |

**Why?**
- **Micro trips are discounted** because competition is high (Rapido, Ola, etc.)
- **Medium trips have a slight premium** because fewer competitors serve this range
- The multiplier applies only to the distance component, NOT the base fare

```
raw_subtotal = base_fare + (distance_component × band_multiplier)
```

### Stage E: Zone-Level Surcharges (Industry Standard)

These are configurable per zone and follow patterns used by Cogoport, ShipX, and other logistics platforms:

| Surcharge | Description | Default |
|-----------|-------------|---------|
| **Fuel Surcharge (FSC)** | % added when fuel prices spike | 0% (enable when needed) |
| **Zone Type Multiplier (SLS)** | Premium/discount by area type | 1.0x (varies by zone type) |
| **ODA Surcharge** | Extra charge when BOTH pickup AND drop are in remote areas | 5% (only when both ODA) |
| **Special Location Fee** | Flat fee for airports, tech parks | Rs 0 (set per zone) |

```
raw_subtotal = raw_subtotal × zone_type_multiplier × oda_multiplier
             + fuel_surcharge + special_location_fee
```

### Stage F: Dynamic Surge (Production Mode Only)

In production, three dynamic factors adjust pricing in real-time:

#### Layer 1: Traffic Multiplier

Based on actual traffic conditions from Google Maps:

```
traffic_ratio = time_in_traffic / normal_time
```

| Traffic Condition | Ratio | Multiplier |
|------------------|-------|------------|
| No traffic | < 1.0 | 1.0x (no change) |
| Light traffic | 1.0 - 1.5 | 1.0x - 1.1x |
| Moderate traffic | 1.5 - 2.0 | 1.1x - 1.15x |
| Heavy traffic | 2.0 - 3.0 | 1.15x - 1.2x |
| Extreme congestion | > 3.0 | 1.2x (capped) |

Uses a smooth curve: `1 + 0.5 × (ratio - 1)^0.8`, capped at 1.2x.

#### Layer 2: Time-of-Day Surge

Different demand patterns by time and vehicle category:

| Period | Small Vehicles | Mid Vehicles | Heavy Vehicles |
|--------|---------------|--------------|----------------|
| Morning (6-12) | 0.98x | 0.98x | 1.00x |
| Afternoon (12-18) | 1.02x | 1.05x | 1.05x |
| Evening (18-6) | 1.00x | 1.15x | 1.10x |

The evening surge is strongest for mid-size vehicles (commercial demand drops, but delivery demand stays).

This multiplier is also **distance-scaled**: micro trips get the full surge effect (1.5x), while long trips get a dampened effect (0.7x).

#### Layer 3: Zone Demand Multiplier

Location-based demand factor from the `PricingZoneMultiplier` table. Adjusts for areas with consistently high/low demand.

#### Combined Surge Cap

```
combined_surge = min(traffic × time × zone_demand, 2.0)
```

**Hard cap at 2.0x** - the price never more than doubles due to surge, protecting customers from extreme pricing.

> **Note:** In calibration mode and for time-aware zone pricing (Tiers 1 & 3), ALL surge multipliers are set to 1.0. This prevents double-counting since the base rates already encode time-of-day demand.

### Stage G: Final Multipliers

```
final = raw_subtotal × combined_surge × vehicle_multiplier × city_multiplier
      × (1 + variance_buffer + high_value_buffer)
      × (1 + margin)
```

| Factor | Current Value | Purpose |
|--------|--------------|---------|
| `vehicle_multiplier` | 1.0 | Future: adjust by vehicle availability |
| `city_multiplier` | 1.0 | Future: city-level cost-of-living adjustment |
| `variance_buffer` | 0% | Safety buffer for estimation errors |
| `high_value_buffer` | 0% | Extra charge for high-value items (when configured) |
| `margin` | 0% | Explicit margin (currently rely on guardrail instead) |

### Stage H: Rounding

| Mode | Rounding | Example |
|------|----------|---------|
| Production | Nearest Rs 10 | Rs 153 → Rs 150, Rs 157 → Rs 160 |
| Calibration | Exact (nearest paisa) | Rs 153.42 → Rs 153 |

---

## 5. Unit Economics Guardrail

After calculating the price, the engine checks profitability. **We never lose money on a trip.**

### Cost Breakdown per Order

| Cost Component | Calculation |
|---------------|-------------|
| Vendor cost | = raw_subtotal (what we pay the driver) |
| Payment gateway fee | = 2% of final price |
| Support buffer | = Rs 2 per order (customer support) |
| Maps API cost | = Rs 0.10 per order (Google Maps) |
| **Total cost** | = vendor + PG fee + support + maps |

### Margin Check

```
margin_pct = (final_price - total_cost) / total_cost × 100
```

**If margin < 5%:**
1. Calculate the minimum price needed for 5% margin
2. Round UP to nearest Rs 10 (ceiling, to preserve margin)
3. Apply as the final price

**Example:**
- Raw price = Rs 95
- Total cost = Rs 95 + Rs 1.90 (PG) + Rs 2 + Rs 0.10 = Rs 99
- Margin = (95 - 99) / 99 = -4% (losing money!)
- Required price = Rs 99 × 1.05 = Rs 103.95
- Guardrail price = Rs 110 (ceil to nearest Rs 10)
- Final margin = (110 - 101.30) / 101.30 = 8.6% (healthy)

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

All time calculations use the **city's local timezone** (Asia/Kolkata for Hyderabad) to avoid UTC mismatches.

---

## Pricing Flow Diagram

```
Customer Request
    │
    ├── pickup_lat, pickup_lng
    ├── drop_lat, drop_lng
    ├── vehicle_type
    └── quote_time
         │
         ▼
┌─────────────────────┐
│   Route Resolver     │ ── Google Maps API (cached 2h)
│   distance, traffic  │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   Zone Resolution    │ ── Which zones contain pickup & drop?
│   pickup_zone        │    (55 zones, priority-ordered)
│   drop_zone          │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐    Tier 1: Corridor pricing?
│   Pricing Resolution │ → Tier 2: Inter-zone formula?
│   base_fare          │ → Tier 3: Zone + time override?
│   per_km_rate        │ → Tier 4: Zone override?
│   source             │ → Tier 5: City default
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   Price Calculation  │
│                      │
│   base_fare          │ ← Fixed "show up" cost
│ + distance_component │ ← Slab-based per-km charges
│ × band_multiplier    │ ← Micro/Short/Medium/Long shaping
│ × zone_type_mult     │ ← Area type premium/discount
│ × oda_mult           │ ← Remote area surcharge
│ + fuel_surcharge     │ ← Fuel price pass-through
│ + location_fee       │ ← Airport/tech park flat fee
│ × traffic_surge      │ ← Real-time traffic (1.0-1.2x)
│ × time_surge         │ ← Time-of-day demand (0.98-1.15x)
│ × zone_demand_surge  │ ← Location demand factor
│   [cap at 2.0x]      │ ← Customer protection
│                      │
│ → Round to Rs 10     │
│ → Apply price floor  │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   Guardrail Check    │
│                      │
│   total_cost =       │
│     vendor_cost      │
│   + 2% PG fee        │
│   + Rs 2 support     │
│   + Rs 0.10 maps     │
│                      │
│   if margin < 5%:    │
│     bump to 5%       │
│     ceil to Rs 10    │
└────────┬────────────┘
         │
         ▼
    Final Price (Rs)
```

---

## Calibration

The engine is calibrated against **Porter** (India's leading intra-city logistics platform) using:

- **10 routes** across Hyderabad (micro to long-haul)
- **3 time bands** (morning, afternoon, evening)
- **7 vehicle types** (two_wheeler to canter_14ft)
- **= 210 test scenarios**

**Tolerance:** -3% to +16% vs Porter prices
- Can be up to 3% cheaper (competitive positioning)
- Can be up to 16% more expensive (unit economics guardrail may bump small orders)

**Current status:** 210/210 scenarios passing (100%)

---

## Key Design Decisions

1. **YAML-driven configuration** - Zone rates, slabs, and adjustments are in YAML files, not hardcoded. This makes it easy to add new cities or tweak rates without code changes.

2. **Time-aware zone pricing bypasses surge** - When we have explicit morning/afternoon/evening rates for a zone, the dynamic surge layers (traffic, time, demand) are set to 1.0. This prevents double-counting since the time-specific rates already factor in demand patterns.

3. **Distance band shaping on distance only, not base fare** - The base fare is a fixed cost (driver showing up). Only the variable distance component is shaped by the distance band multiplier.

4. **Guardrail uses ceiling rounding** - When the margin check bumps the price, it rounds UP to the nearest Rs 10 to ensure the margin is preserved. Regular rounding uses standard rounding (nearest Rs 10).

5. **2-hour cache windows** - Route data (especially traffic) is cached in 2-hour buckets. This balances API costs against data freshness.
