# SwapZen Hyperlocal Pricing Platform Plan

## Goal

Build a launch-ready pricing platform for SwapZen's hyperlocal delivery business that can:

- quote reliably at launch,
- protect unit economics,
- adapt in real time as supply and demand change,
- support operator control and safe rollouts,
- evolve into a model-driven pricing system without replacing the whole stack.

This plan is for `SwapZen hyperlocal delivery first`, not a generic logistics plus ride-hailing platform.

## Current State (March 2026)

The platform has been built through multiple phases and is now launch-ready:

### Implemented

- **H3 Zone System**: 90 zones in Hyderabad defined by H3 R7 hex cells (~740 cells)
- **Full Pricing Coverage**: All 90 zones × 10 vehicles × 3 time bands = 2,700 time pricings
- **Corridor Pricing**: 77 zone pairs with explicit rates for all 10 vehicles
- **Distance Slabs**: 40 telescoping per-km rate tiers (4 per vehicle)
- **City Defaults**: 10 PricingConfig records (one per vehicle type)
- **Inter-Zone Formula**: Weighted 60/40 blend with 9 zone-type adjustments
- **Two-Sided Pricing**: Vendor rate cards, margin prediction per quote
- **Per-Minute + Dead-KM**: Time and pickup-distance components
- **Approval Workflow**: Draft → pending → approved → rejected
- **Drift Detection**: Auto-computed on PricingActual create
- **Backtesting**: Replay quotes against candidate configs
- **Control Plane**: Audit logs, feature flags, emergency freeze
- **Market State**: Outcome tracking, pressure map by zone/vehicle/time
- **Merchant Policies**: Floor/cap/markup/discount/fixed_rate per merchant
- **Shadow Model**: Candidate price optimizer, model scoring per quote
- **Admin Dashboard**: Zone map (hex grid), pricing matrix, toggle controls

### Single Source of Truth

```
config/zones/hyderabad/h3_zones.yml  → zones + H3 cells + pricing
config/zones/hyderabad/vehicle_defaults.yml  → global rates, slabs, inter-zone formula
```

Sync command: `rails zones:h3_sync[hyd]`

## Product Focus

Launch scope stays narrow:

1. Hyderabad first
2. Hyperlocal delivery first
3. All 10 vehicle families:
   - Small: `two_wheeler`, `scooter`
   - Mid: `mini_3w`, `three_wheeler`, `three_wheeler_ev`, `tata_ace`, `pickup_8ft`
   - Heavy: `eeco`, `tata_407`, `canter_14ft`
4. Product modes:
   - instant delivery
   - scheduled delivery
   - merchant / enterprise repeat lanes

## Pricing Principles

Pricing should optimize for profitable order capture, not competitor imitation.

Each quote should move toward this objective:

`expected_contribution = P(book) * (price - expected_cost - expected_risk_cost)`

subject to:

- margin floor
- SLA / ETA protection
- fairness caps
- merchant contract limits
- city / product policy rules

Competitor price is an input, not the target.

## What The Platform Must Become

### 1. Deterministic Core (DONE)

The zone and corridor engine serves as the fallback and explainability layer:
- Quotes when live features are unavailable
- Enforces safe floor and cap rules
- Provides human-readable breakdowns
- Supports launch before models are trusted

### 2. Market State Layer (INFRASTRUCTURE DONE)

Real-time state by area, vehicle family, and time bucket:
- Outcome tracking (accepted/rejected/expired)
- Pressure map by zone
- Next: live supply snapshots, pickup ETA, demand pressure

### 3. Model Layer (INFRASTRUCTURE DONE)

Shadow model framework in place:
- `pricing_model_configs` and `pricing_model_scores` tables
- `CandidatePriceOptimizer` scores every quote
- Next: train actual models on accumulated data

### 4. Policy Engine (DONE)

Merchant policies combine rules with deterministic pricing:
- Floor, cap, markup, discount, fixed_rate per merchant
- QuoteEngine accepts `merchant_id`

### 5. Control Plane (DONE)

Operators have:
- Versioned configs with approval workflow
- Audit trail (`pricing_change_logs`)
- Feature flags (`pricing_rollout_flags`)
- Emergency freeze (`pricing_emergency_freezes`)
- Admin dashboard with zone map and pricing controls

### 6. Replay And Audit (DONE)

Every quote decision is stored with:
- Request parameters
- Route result
- Pricing source and breakdown
- Drift columns (filled on actual cost)
- Backtest replay capability

## Remaining Roadmap

### Phase 2: Time Band Expansion
- Expand from 3 → 6 time bands
- Day-of-week awareness (weekday vs weekend)

### Phase 3: External Factors
- Weather-based surge
- Fuel price indexing
- Demand proxy from order velocity

### Phase 4: Physical Dimensions
- Weight/volume pricing tiers
- Toll charges
- Multi-stop pricing

### Phase 5: Learning System
- Feedback loop from actuals → model retraining
- Auto-calibration when drift exceeds thresholds
- A/B testing framework

### Multi-City Expansion
- Bangalore, Mumbai, Delhi
- Per-city H3 zone definitions
- City-specific vehicle defaults

## Launch KPIs

Primary:

1. Quote success rate
2. Quote-to-book conversion
3. Contribution margin by vehicle and lane
4. Pickup SLA hit rate
5. Cancellation rate

Secondary:

1. Actual cost drift vs estimated cost
2. Price volatility by area and hour
3. Courier / partner acceptance
4. Merchant repeat rate
5. Refund / complaint rate

## Non-Negotiables

1. No opaque ML-only pricing at launch
2. No multi-city rollout before one-city replay is solid
3. No single policy family for parcel and passenger use cases
4. Every live price must have reason codes
5. Every pricing change must be rollbackable
6. Every experiment must have guardrails
