# SwapZen Hyperlocal Pricing Platform Plan

## Goal

Build a launch-ready pricing platform for SwapZen's hyperlocal delivery business that can:

- quote reliably at launch,
- protect unit economics,
- adapt in real time as supply and demand change,
- support operator control and safe rollouts,
- evolve into a model-driven pricing system without replacing the whole stack.

This plan is for `SwapZen hyperlocal delivery first`, not a generic logistics plus ride-hailing platform.

## Product Focus

Launch scope should stay narrow:

1. Hyderabad first
2. Hyperlocal delivery first
3. Vehicle families first:
   - `two_wheeler`
   - `three_wheeler` / `mini_3w`
   - `tata_ace` / `pickup_8ft`
4. Product modes first:
   - instant delivery
   - scheduled delivery
   - merchant / enterprise repeat lanes

Ride-hailing and broader intercity logistics should be treated as later policy families, not part of the launch engine.

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

### 1. Deterministic Core

Keep the current zone and corridor engine as the fallback and explainability layer.

Responsibilities:

- quote when live features are unavailable,
- enforce safe floor and cap rules,
- provide human-readable breakdowns,
- support launch before models are trusted.

### 2. Market State Layer

Add real-time state by area, vehicle family, and time bucket:

- online supply
- idle supply
- pickup ETA
- demand pressure
- acceptance rate
- cancellation rate
- deadhead risk
- route traffic
- rain / event pressure
- merchant lane behavior

### 3. Model Layer

Add separate models for:

- expected fulfillment cost
- courier / partner acceptance
- booking conversion / price elasticity
- cancellation risk
- SLA breach risk
- backhaul probability
- fraud / abuse risk
- competitor / market reference estimate

### 4. Policy Engine

A policy engine should combine deterministic rules, market state, and model scores to choose a price from a bounded candidate ladder.

### 5. Control Plane

Operators need:

- versioned policies
- approval workflow
- rollback
- experiment controls
- merchant overrides
- city / vehicle rollout flags

### 6. Replay And Audit

Every quote decision must be replayable offline with:

- request
- route result
- features
- candidate prices
- chosen price
- policy version
- reason codes
- booking outcome
- actual fulfillment cost

## Launch Architecture

### Phase A: Launch-Safe Foundation

Required before launch:

1. YAML sync must create quote-ready defaults
2. Config versioning must clone child state
3. Admin changes must be authenticated and audited
4. One zone source of truth must drive base pricing and demand logic
5. Scheduled pricing must use scheduled route context, not `now`
6. Deterministic regression checks must exist

### Phase B: Post-Launch Learning Loop

Required within the first 4 to 8 weeks after launch:

1. capture quote outcomes
2. capture booking and dispatch outcomes
3. capture actual vendor / partner cost
4. capture cancellations and refunds
5. capture city-area supply snapshots
6. build replay dashboards

### Phase C: Real-Time Optimization

After enough data exists:

1. shadow-score cost and conversion models
2. compare model suggestions with live decisions
3. activate bounded optimization by cohort
4. keep deterministic fallback live at all times

## Repo-Level Roadmap

### Foundation Work

1. Make `zones:sync` the real bootstrap path
2. Remove dependence on ad hoc seed state for pricing defaults
3. Version child records with parent pricing configs
4. Add launch-focused documentation and operator workflow

### Productization Work

1. Add `quote_decisions` event log
2. Add `booking_outcomes` event log
3. Add `dispatch_events` event log
4. Add `actual_costs` event log
5. Add `policy_versions` and `experiments`

### Real-Time Work

1. Add area-time state snapshots
2. Add real-time feature store inputs
3. Add model inference hooks
4. Add candidate-price optimization

## Launch KPIs

Primary:

1. quote success rate
2. quote-to-book conversion
3. contribution margin by vehicle and lane
4. pickup SLA hit rate
5. cancellation rate

Secondary:

1. actual cost drift vs estimated cost
2. price volatility by area and hour
3. courier / partner acceptance
4. merchant repeat rate
5. refund / complaint rate

## Non-Negotiables

1. No opaque ML-only pricing at launch
2. No multi-city rollout before one-city replay is solid
3. No single policy family for parcel and passenger use cases
4. Every live price must have reason codes
5. Every pricing change must be rollbackable
6. Every experiment must have guardrails

## First Implementation Slice

The first implementation slice in this repo should make the launch bootstrap trustworthy:

1. `zones:sync` creates current `PricingConfig` defaults from YAML vehicle defaults
2. distance slabs are created from YAML and tied to those configs
3. versioned config updates preserve slabs and surge rules

This keeps the existing engine usable for SwapZen launch while opening the path to real-time and model-driven pricing later.
