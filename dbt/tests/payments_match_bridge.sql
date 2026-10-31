SELECT
    p.total_payment_amount,
    b.total_allocated_amount
FROM (
    SELECT SUM(payment_amount) AS total_payment_amount
    FROM {{ ref('fact_payment') }}
    WHERE is_cleared = 1
) p
CROSS JOIN (
    SELECT SUM(allocated_amount) AS total_allocated_amount
    FROM {{ ref('bridge_payment_application') }}
    WHERE application_type = 'payment'
) b
WHERE p.total_payment_amount <> b.total_allocated_amount
