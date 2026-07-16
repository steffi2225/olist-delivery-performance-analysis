/* =====================================================
   SECTION 1: CLEAN CUSTOMER TABLE
===================================================== */
CREATE OR REPLACE VIEW `revou-sql-class-402216.olist_dataset.clean_customer` AS
SELECT 
  customer_id,
  customer_city,
  customer_state,
  customer_zip_code_prefix,
  customer_unique_id,
CASE WHEN customer_state IN ('AC','AP','PA','AM','RO','RR','TO') THEN 'North'
    WHEN customer_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
    WHEN customer_state IN ('GO','MT','MS','DF') THEN 'Central-West'
    WHEN customer_state IN ('ES','MG','RJ','SP') THEN 'Southeast'
    WHEN customer_state IN ('PR','RS','SC') THEN 'South'
    ELSE 'unknown'
END AS customer_region 
FROM `revou-sql-class-402216.olist_dataset.customers`;

/* =====================================================
   SECTION 2: CLEAN SELLER TABLE
===================================================== */
CREATE OR REPLACE VIEW `revou-sql-class-402216.olist_dataset.clean_seller` AS
SELECT 
  seller_id,
  seller_city,
  seller_state,
  seller_zip_code_prefix,
CASE WHEN seller_state IN ('AC','AP','PA','AM','RO','RR','TO') THEN 'North'
    WHEN seller_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Northeast'
    WHEN seller_state IN ('GO','MT','MS','DF') THEN 'Central-West'
    WHEN seller_state IN ('ES','MG','RJ','SP') THEN 'Southeast'
    WHEN seller_state IN ('PR','RS','SC') THEN 'South'
    ELSE 'unknown'
END AS seller_region 
FROM `revou-sql-class-402216.olist_dataset.sellers`;

/* =====================================================
   SECTION 3: MONTHLY ORDER
===================================================== */
SELECT DATE_TRUNC (DATE (order_purchase_timestamp), MONTH) AS order_month,
  COUNT (order_id) AS total_order
FROM `revou-sql-class-402216.olist_dataset.order`
GROUP BY order_month
ORDER BY order_month ASC;


/* =====================================================
   SECTION 4: DELIVERY STATUS AND REVIEW SCORE
===================================================== */
SELECT CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'on-time'
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'delayed'
            ELSE 'un-known'
            END AS delivery_status,
        r.review_score,
        COUNT (DISTINCT o.order_id) AS total_transaction
FROM `revou-sql-class-402216.olist_dataset.order` o
JOIN `revou-sql-class-402216.olist_dataset.reviews` r
  ON o.order_id = r.order_id
WHERE o.order_status = 'delivered' 
  AND DATE (o.order_purchase_timestamp) >= '2017-01-01'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY review_score, delivery_status
ORDER BY review_score, delivery_status;


/* =====================================================
   SECTION 5: CREATE DELAY BUCKET IN ORDER TABLE
===================================================== */
SELECT order_id,
  customer_id,
  order_status,
  DATE (order_purchase_timestamp) AS purchase_date,
  DATE (order_delivered_customer_date) AS delivery_date,
  DATE (order_estimated_delivery_date) AS estimated_delivery_date,
  DATE_DIFF(DATE(order_delivered_customer_date),DATE(order_estimated_delivery_date),DAY) AS delay_days,
  CASE WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) <=0 THEN 'on-time'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 1 AND 3 THEN '1-3 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 4 AND 7 THEN '4-7 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 8 AND 30 THEN '8-30 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 31 AND 60 THEN '31-60 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 61 AND 90 THEN '61-90 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 91 AND 120 THEN '91-120 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) > 120 THEN '>120 days late'
        ELSE 'unknown'
            END AS delay_bucket
FROM `revou-sql-class-402216.olist_dataset.order`;


/* =====================================================
   SECTION 6: PRODUCT BY DELAY BUCKET
===================================================== */
WITH order_level AS (
SELECT o.order_id,
      t.product_name_eng AS product_category,
    DATE_DIFF(
        DATE(o.order_delivered_customer_date),
        DATE(o.order_estimated_delivery_date),
        DAY
    ) AS delayed_days
FROM `revou-sql-class-402216.olist_dataset.order` o
JOIN `revou-sql-class-402216.olist_dataset.items` i
    ON o.order_id = i.order_id
JOIN `revou-sql-class-402216.olist_dataset.product` p
  ON i.product_id = p.product_id
JOIN `revou-sql-class-402216.olist_dataset.product_in_english` t
  ON p.product_category_name = t.product_name_porto
WHERE o.order_status = 'delivered'
  AND DATE(o.order_purchase_timestamp) >= '2017-01-01'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_delivered_customer_date > o.order_estimated_delivery_date
GROUP BY
    o.order_id,
    product_category,
    delayed_days
)

SELECT
    product_category,
    CASE
        WHEN delayed_days BETWEEN 1 AND 3
            THEN '1-3 days late'
        WHEN delayed_days BETWEEN 4 AND 7
            THEN '4-7 days late'
        WHEN delayed_days BETWEEN 8 AND 30
            THEN '8-30 days late'
        WHEN delayed_days BETWEEN 31 AND 60
            THEN '31-60 days late'
        WHEN delayed_days BETWEEN 61 AND 90
            THEN '61-90 days late'
        WHEN delayed_days BETWEEN 91 AND 120
            THEN '91-120 days late'
        WHEN delayed_days > 120
            THEN '>120 days late'
        ELSE 'check'
    END AS delay_bucket,
    COUNT(DISTINCT order_id) AS total_orders
FROM order_level
GROUP BY
    product_category,
    delay_bucket
ORDER BY
    total_orders DESC,
    delay_bucket;

/* =====================================================
   SECTION 7: AVERAGE RATING SCORE BY DELAY BUCKET
===================================================== */
SELECT CASE WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) <=0 THEN 'on-time'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 1 AND 3 THEN '1-3 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 4 AND 7 THEN '4-7 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 8 AND 30 THEN '8-30 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 31 AND 60 THEN '31-60 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 61 AND 90 THEN '61-90 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) BETWEEN 91 AND 120 THEN '91-120 days late'
            WHEN DATE_DIFF(order_delivered_customer_date, order_estimated_delivery_date, DAY) > 120 THEN '>120 days late'
        ELSE 'check'
            END AS delivery_days,
        COUNT (DISTINCT o.order_id) AS total_transaction,
        ROUND (AVG (review_score), 2) AS rating_score
FROM `revou-sql-class-402216.olist_dataset.order` o
JOIN `revou-sql-class-402216.olist_dataset.reviews` r
  ON o.order_id = r.order_id
WHERE o.order_status = 'delivered' 
  AND DATE (o.order_purchase_timestamp) >= '2017-01-01'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_days
ORDER BY delivery_days ASC;
















