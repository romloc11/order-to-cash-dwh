{{ config(severity='warn') }}

SELECT
    order_id,
    customer_id,
    order_date,
    balance_at_order,
    total_amount,
    credit_limit,
    was_held_credit_limit
FROM {{ ref('fact_web_order') }}
WHERE (CASE WHEN balance_at_order + total_amount > credit_limit THEN 1 ELSE 0 END) <> was_held_credit_limit