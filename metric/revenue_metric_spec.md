### Global Quality Guardrails (all metrics)

**Data reliability**

* **Freshness / latency:** D-1 vs D-2 completeness, late-arriving events monitoring
* **Dedup health:** duplicate rate for `order_line_id`, `payment_id`, `delivery_event_id`
* **Coverage:** required timestamps coverage (`paid_at`, `delivered_at`), non-null `price/qty`
* **Timezone & FX consistency:** single TZ cut-off; FX rule = by event date (paid/delivered)
* **Internal/test filtering:** internal users, QA orders, sandbox merchants excluded
* **Outlier monitoring:** top-N buyers/orders, extreme `price/qty` checks


## 1) GMV_booked_paid

* **Business intent:** demand + checkout performance (GMV captured at successful payment)
* **Grain:** `order_line_id`
* **Definition (Numerator):** `SUM(qty * unit_price_gross)` *(tax/shipping/discount inclusion explicitly defined)*
* **Time attribution:** calendar day/week/month by `paid_at` (+ optional rolling 7D/30D)
* **Inclusion:** `payment_status = 'success'` (or `paid_flag = 1`)
* **Exclusion:**

* internal/test, fraud/chargeback flagged
* duplicate payment retries (dedupe by `payment_id`)
* invalid `qty/price` (0 or negative) per business rule

* **Edge cases:** multi-currency (FX by `paid_at`), split payments, partial cancellations, gifts `price=0`, duplicate joins from retries
* **Sanity checks (3):**

1. line→order reconciliation bridge (tax/shipping/discount deltas)
2. `paid_at` coverage + payment success rate trend
3. outlier drill (top 20 lines/buyers)

* **Guardrails to read it correctly**

* Payment success rate (gateway issues can fake GMV drops)
* Checkout conversion rate
* Refund rate (booked GMV healthy, net deteriorating bo‘lishi mumkin)

---

## 2) GMV_fulfilled_delivered

* **Business intent:** ops execution (GMV recognized at delivery)
* **Grain:** `order_line_id` *(supports partial delivery via `delivered_qty`)*
* **Definition:** `SUM(delivered_qty * unit_price_gross)` *(discount/tax/shipping treatment defined)*
* **Time attribution:** by `delivered_at`
* **Inclusion:** `order_line_status = 'delivered'` *(COD/capture rules explicitly stated if needed)*
* **Exclusion:** internal/test, fraud, replacement/reship flagged, duplicate delivery events (dedupe by `delivery_event_id` or `(order_line_id, delivered_at)` rule)

* **Edge cases:** partial delivery, month-end TZ cut-off, FX by `delivered_at`, reshipments, “delivered twice”
* **Sanity checks (3):**

1. booked vs fulfilled bridge (WIP/backlog)
2. paid→delivered lag distribution (median/p90)
3. delivered coverage (delivered lines vs delivered orders)

* **Guardrails**

* Backlog/WIP = `GMV_booked_paid − GMV_fulfilled_delivered` trend
* Cancel rate + On-time delivery (OTD)
* Geo/distance mix (lag/throughput shifts)

---

## 3) Gross Revenue — Marketplace (commission/fees)

* **Metric:** `Gross_Revenue_marketplace`
* **Business intent:** platform topline revenue from fees/commission
* **Grain:** order line or order *(use lowest grain that avoids double counting)*
* **Definition:** `SUM(commission_fee + service_fee + platform_delivery_fee)` *(delivery fee ownership explicit)*
* **Time attribution:** pick 1 recognition timestamp and standardize (`paid_at` or `delivered_at`)
* **Inclusion:** population aligns with recognition rule (paid/delivered)
* **Exclusion:** internal/test, reversed fee postings, duplicate fee rows (dedupe by `fee_id` / `payment_id`)
* **Edge cases:** fee waivers, contract sellers, FX for fees, fee reversals post-refund
* **Sanity checks (3):**

1. Take-rate bounds (`Revenue/GMV` plausible range)
2. component bridge (commission vs service vs delivery)
3. concentration (top sellers share)

* **Guardrails**

* Always track **Take Rate** alongside revenue (volume vs monetization)
* Refund/chargeback adjustments (gross stable, net erode bo‘lishi mumkin)

---

## 4) Gross Revenue — Retail (Net Sales)

* **Metric:** `Gross_Revenue_retail` *(aka Net_Sales — naming must match finance definition)*
* **Business intent:** retailer-first topline sales
* **Grain:** order or order line
* **Definition:** `SUM(paid_amount)` *(tax/shipping inclusion explicit)*
* **Time attribution:** by `paid_at` (or accounting recognition rule)
* **Inclusion:** `payment_status='success'`
* **Exclusion:** internal/test, reversed payments, duplicate captures
* **Edge cases:** partial refunds, split tender, FX, post-period adjustments
* **Sanity checks (3):**

1. payment gateway reconciliation
2. `paid_at` coverage + payment success trend
3. outlier drill

* **Guardrails**

* If possible: COGS → Gross Margin (revenue ≠ profit)
* Discount rate (margin collapse with stable revenue)

---

## 5) Take Rate

* **Metric:** `Take_Rate_(paid|delivered)` *(name must encode denominator choice)*
* **Business intent:** monetization efficiency (revenue captured per GMV)
* **Grain:** period-level (day/week/month), segmentable (category/region/channel)
* **Definition:** `Gross_Revenue_marketplace / GMV_(paid|delivered)` *(must align population/time)*
* **Window:** rolling 7D/30D + calendar month
* **Edge cases:** near-zero GMV days, fee waivers, contract sellers
* **Sanity checks (3):**

1. bounds & stability
2. Simpson check by segment
3. reconciliation with fee policy changes

* **Guardrails**

* Mix shifts can move take rate without policy change → always segment
* Promo subsidies separate tracked (take rate ↑ while net ↓)

---

## 6) AOV (GMV per order)

* **Metric:** `AOV_gmv_(paid|delivered)`
* **Business intent:** basket size / price & mix signal
* **Definition:** `GMV_(paid|delivered) / COUNT(DISTINCT order_id)` *(must match paid vs delivered choice)*
* **Window:** rolling 7D/30D + month
* **Edge cases:** bulk buyers, extreme outliers, multi-item orders
* **Sanity checks (3):**

1. mean vs median/p90
2. outlier impact test
3. segment Simpson check

* **Guardrails**

* Track orders + conversion alongside AOV
* Discount rate (AOV drop promo-driven bo‘lishi mumkin)

---

## 7) Revenue per Visitor (RPV)

* **Metric:** `RPV_(revenue|gmv)` *(numerator choice encoded)*
* **Business intent:** revenue density per unit traffic (funnel efficiency)
* **Grain:** visitor-day or session-day *(choose one)*
* **Definition:** `(Gross Revenue or GMV) / COUNT(DISTINCT visitor_id)` *(bot-filtered)*
* **Window:** rolling 7D/30D
* **Inclusion:** valid traffic
* **Exclusion:** bots, internal/QA, spam channels
* **Edge cases:** tracking breaks, cookie loss, attribution changes
* **Sanity checks (3):**

1. decomposition: `RPV ≈ Conversion * AOV`
2. bot-filter sensitivity
3. channel mix check

* **Guardrails**

* Instrumentation/event coverage monitoring (RPV sensitive)
* Always segment by acquisition channel

---

## 8) Net Revenue (via bridge)

* **Metric:** `Net_Revenue`
* **Business intent:** post-adjustment revenue closer to economics
* **Grain:** prefer order line (partial refunds/returns support)
* **Definition:** `Gross Revenue − Refunds/Returns − Platform Promo Subsidy − Chargebacks/Allowances` *(component list explicit)*
* **Time attribution:** choose one and standardize (paid-based or delivered-based); document refund lag policy
* **Exclusion:** internal/test + duplicated adjustments
* **Edge cases:** refund lag into later periods, chargeback delays, negative net lines
* **Sanity checks (3):**

1. gross→net reconciliation bridge table
2. lag sensitivity (month-end)
3. bounds & outlier drill

* **Guardrails**

* Always show component breakdown (no “black box net”)
* Promo evaluation: net-based (gross can overstate)

