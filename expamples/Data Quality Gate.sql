-- 1) Stop-the-line: Uniqueness (PK / composite key)
--1.1 orders: order_id
-- SUMMARY
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS distinct_order_id,
  (COUNT(*) - COUNT(DISTINCT order_id)) AS duplicate_rows
FROM stg_olist_orders;

-- SAMPLES (agar duplicate_rows > 0 bo'lsa)
SELECT order_id, COUNT(*) AS cnt
FROM stg_olist_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 20;

-- 1.2 order_items: (order_id, order_item_id) unique
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT (order_id, order_item_id)) AS distinct_key,
  (COUNT(*) - COUNT(DISTINCT (order_id, order_item_id))) AS duplicate_rows
FROM stg_olist_order_items;

SELECT order_id, order_item_id, COUNT(*) cnt
FROM stg_olist_order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 20;

-- 1.3 payments: (order_id, payment_sequential) unique
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT (order_id, payment_sequential)) AS distinct_key,
  (COUNT(*) - COUNT(DISTINCT (order_id, payment_sequential))) AS duplicate_rows
FROM stg_olist_order_payments;

--1.4 products / sellers / customers PK unique
SELECT COUNT(*) total, COUNT(DISTINCT product_id) distinct_id,
       COUNT(*) - COUNT(DISTINCT product_id) dup
FROM stg_olist_products;

SELECT COUNT(*) total, COUNT(DISTINCT seller_id) distinct_id,
       COUNT(*) - COUNT(DISTINCT seller_id) dup
FROM stg_olist_sellers;

SELECT COUNT(*) total, COUNT(DISTINCT customer_id) distinct_id,
       COUNT(*) - COUNT(DISTINCT customer_id) dup
FROM stg_olist_customers;


-- 2) Stop-the-line: FK coverage 
-- 2.1 order_items → orders
SELECT
  COUNT(*) AS order_items_rows,
  COUNT(*) FILTER (WHERE o.order_id IS NULL) AS missing_orders,
  (COUNT(*) FILTER (WHERE o.order_id IS NULL))::numeric / NULLIF(COUNT(*),0) AS missing_rate
FROM stg_olist_order_items oi
LEFT JOIN stg_olist_orders o ON o.order_id = oi.order_id;

-- 2.2 order_items  -> products
SELECT
  COUNT(*) AS rows,
  COUNT(*) FILTER (WHERE p.product_id IS NULL) AS missing_products,
  (COUNT(*) FILTER (WHERE p.product_id IS NULL))::numeric / NULLIF(COUNT(*),0) AS missing_rate
FROM stg_olist_order_items oi
LEFT JOIN stg_olist_products p ON p.product_id = oi.product_id;

-- 2.3 order_items  -> sellers
SELECT
  COUNT(*) AS rows,
  COUNT(*) FILTER (WHERE s.seller_id IS NULL) AS missing_sellers,
  (COUNT(*) FILTER (WHERE s.seller_id IS NULL))::numeric / NULLIF(COUNT(*),0) AS missing_rate
FROM stg_olist_order_items oi
LEFT JOIN stg_olist_sellers s ON s.seller_id = oi.seller_id;

-- 2.4 orders -> customers
SELECT
  COUNT(*) AS rows,
  COUNT(*) FILTER (WHERE c.customer_id IS NULL) AS missing_customers,
  (COUNT(*) FILTER (WHERE c.customer_id IS NULL))::numeric / NULLIF(COUNT(*),0) AS missing_rate
FROM stg_olist_orders o
LEFT JOIN stg_olist_customers c ON c.customer_id = o.customer_id;

-- 3) Completeness: Critical null checks
-- orders null scorecard
SELECT
  AVG((customer_id IS NULL)::int)::numeric AS pct_customer_id_null,
  AVG((order_purchase_timestamp IS NULL)::int)::numeric AS pct_purchase_ts_null,
  AVG((order_status IS NULL)::int)::numeric AS pct_status_null
FROM stg_olist_orders;

-- order_items null scorecard
SELECT
  AVG((price IS NULL)::int)::numeric AS pct_price_null,
  AVG((freight_value IS NULL)::int)::numeric AS pct_freight_null,
  AVG((product_id IS NULL)::int)::numeric AS pct_product_null,
  AVG((seller_id IS NULL)::int)::numeric AS pct_seller_null
FROM stg_olist_order_items;

-- payments null scorecard
SELECT
    AVG((payment_value IS NULL)::int)::numeric as pct_payment_val_null,
    AVG((payment_type IS NULL)::int)::numeric as pct_payment_type_null
FROM stg_olist_order_payments;

-- reviews null scorecard
SELECT
    AVG((review_score IS NULL)::int)::numeric as pct_review_score_null
FROM stg_olist_order_reviews;

-- 4) Validity & Range:(stop-the-line)
-- 4.1 Non-negative amounts
SELECT
  COUNT(*) FILTER (WHERE price < 0) AS neg_price_rows,
  COUNT(*) FILTER (WHERE freight_value < 0) AS neg_freight_rows
FROM stg_olist_order_items;

SELECT
  COUNT(*) FILTER (WHERE payment_value < 0) AS neg_payment_rows
FROM stg_olist_order_payments;

-- 4.2 Date logic (delivered < purchase)
SELECT
    COUNT(*) AS bad_rows
FROM stg_olist_orders
WHERE order_purchase_timestamp IS NULL 
AND order_delivered_customer_date IS NULL
AND order_delivered_customer_date < order_purchase_timestamp;

-- sample
SELECT order_id, order_purchase_timestamp, order_delivered_customer_date
FROM stg_olist_orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp
LIMIT 20;

-- If order status is delivered, order delivered customer date should be available
SELECT COUNT(*) AS bad_rows
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND NOT (
    order_purchase_timestamp <= order_delivered_carrier_date
    AND order_delivered_carrier_date <= order_delivered_customer_date
  );;

-- 4.3 Status enum drift (yangi statuslar)
SELECT order_status, COUNT(*) cnt
FROM stg_olist_orders
GROUP BY order_status
ORDER BY cnt DESC;

-- 5) Coverage: by time “missing days” va spike signal
WITH daily AS (
  SELECT
    date_trunc('day', order_purchase_timestamp)::date AS day,
    COUNT(order_id) AS cnt_orders
  FROM stg_olist_orders
  WHERE order_purchase_timestamp IS NOT NULL
  GROUP BY 1
),
stats AS (
  SELECT AVG(cnt_orders)::numeric AS avg_order_daily
  FROM daily
)
SELECT
  d.day,
  d.cnt_orders,
  s.avg_order_daily,
  (d.cnt_orders::numeric / NULLIF(s.avg_order_daily, 0)) AS vs_avg_ratio
FROM daily d
CROSS JOIN stats s
ORDER BY d.day;

-- item_total sum = payment_value ?
WITH item_sum AS (
  SELECT order_id, SUM(price + freight_value) AS item_total
  FROM stg_olist_order_items
  GROUP BY order_id
),
pay_sum AS (
  SELECT order_id, SUM(payment_value) AS pay_total
  FROM stg_olist_order_payments
  GROUP BY order_id
)
SELECT
  COUNT(*) AS compared_orders,
  COUNT(*) FILTER (WHERE ABS(p.pay_total - i.item_total) > 1) AS mismatch_gt_1,
  AVG(ABS(p.pay_total - i.item_total)) AS avg_abs_diff
FROM item_sum i
JOIN pay_sum p USING (order_id);