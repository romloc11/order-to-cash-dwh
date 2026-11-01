
WITH holds_per_order AS (
    SELECT
        order_id,
        MAX(CASE WHEN hold_reason = 'OVERDUE_BALANCE' THEN 1 ELSE 0 END) AS was_held_overdue,
        MAX(CASE WHEN hold_reason = 'CREDIT_LIMIT' THEN 1 ELSE 0 END) AS was_held_credit_limit,
        MAX(CASE WHEN hold_reason = 'ERP_BLOCK' THEN 1 ELSE 0 END) AS was_held_erp_block
    FROM {{ ref ('ecommerce_order_holds') }}
    GROUP BY order_id
)

SELECT
    o.order_id,
    o.order_number,
    o.customer_id,
    o.status,
    o.total_amount,
    CAST(o.created_at AS DATE) AS order_date,
    ISNULL(f.net_balance, 0) AS balance_at_order,
    ISNULL(f.overdue_15_balance, 0) AS overdue_15_balance,
    f.credit_limit,
    ISNULL(h.was_held_overdue, 0) AS was_held_overdue,
    ISNULL(h.was_held_credit_limit, 0) AS was_held_credit_limit,
    ISNULL(h.was_held_erp_block, 0) AS was_held_erp_block,
    CASE WHEN h.order_id IS NOT NULL THEN 1 ELSE 0 END AS was_held
    FROM {{ ref('ecommerce_orders') }} o
    LEFT JOIN {{ ref('fact_ar_snapshot') }} f
        ON o.customer_id = f.customer_id
        AND CAST(o.created_at AS DATE) = f.snapshot_date
    LEFT JOIN holds_per_order h
        ON o.order_id = h.order_id

