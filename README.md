# Metric Specs & Data Quality Guardrails (E-commerce)

A practical, version-controlled set of **metric specifications** for e-commerce / marketplace analytics.
The goal is to treat metrics as **data contracts**: clear definitions, population rules, edge cases, and sanity checks —
so dashboards and decisions are reproducible and auditable.

## What’s inside

- **Global Quality Guardrails** (freshness, deduplication, coverage, timezone/FX, internal traffic filtering, outliers)
- Core commercial metrics:
  - GMV (Booked/Paid)
  - GMV (Fulfilled/Delivered)
  - Gross Revenue (Marketplace fees/commission)
  - Gross Revenue (Retail / Net Sales)
  - Take Rate
  - AOV
  - Revenue per Visitor (RPV)
  - Net Revenue (bridge approach)

## Repo structure

```text
.
├─ metrics/
│  ├─ metric-specs.md          # Main spec document (definitions + guardrails)
│  
└─ examples/
   └─ sql/                     # Example SQL patterns (dedupe, bridges, sanity checks)
