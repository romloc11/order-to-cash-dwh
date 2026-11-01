SELECT
customer_id,
snapshot_date,
COUNT(customer_id) AS customer_count_per_day
FROM {{ ref('fact_ar_snapshot') }}
GROUP BY customer_id, snapshot_date
HAVING COUNT(customer_id) > 1
