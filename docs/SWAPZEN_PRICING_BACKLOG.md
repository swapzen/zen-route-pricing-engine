# SwapZen Pricing Backlog

## Objective

Turn the current pricing engine into a launch-safe hyperlocal pricing platform for SwapZen, then harden it into a replayable, operator-controlled system that can support serious competition.

## Status

- `Implemented`: quote bootstrap from YAML, config version cloning, scheduled quote routing, admin key split, runtime surge rules
- `Implemented in this slice`: quote decision logging, replay storage, admin replay APIs
- `Next`: approval workflow, actual-cost feedback loop, replay-driven backtesting

## P0

### 1. Quote Decision Logging And Replay
- Status: `implemented`
- Why: every production quote must be auditable and replayable
- Delivered:
  - `pricing_quote_decisions` table
  - `pricing_quote_replays` table
  - decision logger in quote flow
  - admin list/show/replay endpoints

### 2. Pricing Change Approval Workflow
- Status: `pending`
- Why: production pricing changes need maker-checker control and rollback
- Build:
  - draft config versions
  - approval state machine
  - approver identity and notes
  - rollback endpoint

### 3. Actual Cost And Drift Loop
- Status: `next patch`
- Why: standard prices stay standard only if actuals continuously correct the engine
- Build:
  - attach `pricing_actuals` to `pricing_quote_decisions`
  - daily drift report by city, zone, vehicle, pricing source
  - underquote / overquote thresholds
  - replay comparisons against current active configs

### 4. Replay-Driven Backtesting
- Status: `pending`
- Why: config changes should be scored before they hit production
- Build:
  - sample historical quote decisions
  - replay in `original` and `current` modes
  - summarize price delta, variance, and coverage

## P1

### 5. Pricing Admin Control Plane
- Status: `pending`
- Build:
  - scoped roles
  - change history
  - rollout flags by city / vehicle
  - emergency freeze switch

### 6. Supply-Aware Market State
- Status: `pending`
- Build:
  - supply snapshots by geo cell
  - acceptance and cancellation rates
  - pickup ETA pressure
  - policy inputs for demand/supply imbalance

### 7. Merchant And Product Policies
- Status: `pending`
- Build:
  - merchant overrides
  - contract floors and caps
  - product-family-specific pricing rules
  - quote validity tuning by merchant / vehicle

## P2

### 8. Model-Assisted Optimization
- Status: `pending`
- Build:
  - expected-cost model
  - acceptance model
  - cancellation-risk model
  - candidate-price optimizer under hard guardrails

## Recommended Build Order

1. Approval workflow
2. Actual-cost drift loop
3. Replay-driven backtesting
4. Admin control plane
5. Supply-aware market state
6. Merchant policies
7. Model-assisted optimization

## Definition Of Done For Launch-Ready Pricing

1. First-use bootstrap works on a fresh environment
2. Every quote has a decision record
3. Every decision can be replayed from stored inputs and route snapshot
4. Pricing changes require explicit admin approval
5. Daily drift reporting highlights unstable lanes before customers do
