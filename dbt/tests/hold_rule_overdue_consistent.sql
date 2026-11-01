SELECT
    order_id,
    customer_id,
    order_date,
    overdue_15_balance,
    was_held_overdue
FROM {{ ref('fact_web_order') }}
WHERE (CASE WHEN overdue_15_balance > 0 THEN 1 ELSE 0 END) <> was_held_overdue