# SwapZen Pricing Backlog

## Objective

Turn the current pricing engine into a launch-safe hyperlocal pricing platform for SwapZen, then harden it into a replayable, operator-controlled system that can support serious competition.

## Status Overview

| Feature | Status | Phase |
|---------|--------|-------|
| Quote bootstrap from YAML | Implemented | Foundation |
| Config version cloning | Implemented | Foundation |
| Zone-based pricing (H3) | Implemented | Foundation |
| 90 zones × 10 vehicles × 3 bands | Implemented | Foundation |
| Distance slabs (40 records) | Implemented | Foundation |
| Corridor pricing (77 pairs) | Implemented | Foundation |
| H3 zone resolution (R7/R8) | Implemented | Phase C |
| Auto-zone generation | Implemented | Phase D |
| Hex grid visualization | Implemented | Phase D |
| Per-minute pricing | Implemented | Phase A |
| Dead-KM charges | Implemented | Phase A |
| Two-sided pricing (vendor rate cards) | Implemented | Phase B |
| Quote decision logging | Implemented | P0 |
| Approval workflow | Implemented | P0 |
| Drift detection | Implemented | P0 |
| Backtesting | Implemented | P0 |
| Control plane (audit, flags, freeze) | Implemented | P1 |
| Market state (outcomes, pressure) | Implemented | P1 |
| Merchant policies | Implemented | P1 |
| Shadow model scoring | Implemented | P2 |
| H3 zone export/sync (single YAML) | Implemented | H3 Migration |
| Unified admin zones UI | Implemented | H3 Migration |

## Next Up

### Expand Time Bands (Phase 2)
- Status: `pending`
- Expand from 3 time bands (morning/afternoon/evening) to 6 (early_morning, morning, lunch, afternoon, evening, night)
- Add day-of-week awareness (weekday vs weekend rates)

### Weather & External Factors (Phase 3)
- Status: `pending`
- Weather-based surge (rain premium)
- Fuel price indexing
- Demand proxy from order velocity

### Weight/Volume & Multi-Stop (Phase 4)
- Status: `pending`
- Weight and volume-based pricing tiers
- Toll charges integration
- Multi-stop pricing (N stops with distance decay)

### Learning System (Phase 5)
- Status: `pending`
- Feedback loop from actuals → model retraining
- Auto-calibration when drift exceeds thresholds
- A/B testing framework for pricing experiments

## Operational Hardening

### Quote Replay Enhancement
- Status: `pending`
- Replay comparisons against multiple candidate configs simultaneously
- Automated daily replay reports

### Multi-City Expansion
- Status: `pending`
- Bangalore, Mumbai, Delhi zone definitions
- City-specific vehicle defaults and rate cards
- Per-city H3 zone export/sync pipeline

### Real-Time Supply Integration
- Status: `pending`
- Live driver supply snapshots by H3 cell
- Pickup ETA-based pricing adjustments
- Supply-demand imbalance surge

## Definition Of Done For Launch-Ready Pricing

1. First-use bootstrap works on a fresh environment (`zones:h3_sync[hyd]`)
2. Every quote has a decision record
3. Every decision can be replayed from stored inputs and route snapshot
4. Pricing changes require explicit admin approval
5. Daily drift reporting highlights unstable lanes before customers do
6. All 90 zones have full 10-vehicle × 3-band pricing coverage
7. Distance slabs configured for all 10 vehicles (40 records)
8. Corridor pricing for 77 zone pairs × 10 vehicles
9. Vendor rate cards loaded for margin tracking
10. Admin dashboard shows zone map, pricing matrix, and toggle controls
