WITH invoices_open AS (
    SELECT
        d.date_day AS snapshot_date,
        f.customer_id,
        SUM(f.invoice_amount) AS invoice_balance,
        SUM(CASE WHEN f.due_date < d.date_day THEN f.invoice_amount ELSE 0 END) AS overdue_balance,
        SUM(CASE WHEN DATEDIFF(day, f.due_date, d.date_day) > 15 THEN f.invoice_amount ELSE 0 END) AS overdue_15_balance
    FROM {{ ref('dim_date') }} d
    JOIN {{ ref('fact_invoice') }} f
        ON f.invoice_date <= d.date_day
        AND (f.clearing_date IS NULL OR f.clearing_date > d.date_day)
    GROUP BY d.date_day, f.customer_id
),

credits_open AS (
    SELECT
        d.date_day AS snapshot_date,
        x.customer_id,
        SUM(x.amount) AS credits_balance
    FROM {{ ref('dim_date') }} d
    JOIN (
        SELECT customer_id, payment_date AS doc_date, clearing_date, payment_amount AS amount
        FROM {{ ref('fact_payment') }}
        UNION ALL
        SELECT customer_id, credit_memo_date, clearing_date, credit_memo_amount
        FROM {{ ref('fact_credit_memo') }}
    ) x
        ON x.doc_date <= d.date_day
        AND (x.clearing_date IS NULL OR x.clearing_date > d.date_day)
    GROUP BY d.date_day, x.customer_id
)

SELECT
    c.customer_id,
    d.date_day AS snapshot_date,
    ISNULL(i.invoice_balance, 0) AS invoice_balance,
    ISNULL(cr.credits_balance, 0) AS credits_balance,
    ISNULL(i.invoice_balance, 0) - ISNULL(cr.credits_balance, 0) AS net_balance,
    ISNULL(i.overdue_balance, 0) AS overdue_balance,
    ISNULL(i.overdue_15_balance, 0) AS overdue_15_balance,
    h.credit_limit
FROM {{ ref('dim_customer') }} c
CROSS JOIN {{ ref('dim_date') }} d
LEFT JOIN invoices_open i
    ON i.customer_id = c.customer_id AND i.snapshot_date = d.date_day
LEFT JOIN credits_open cr
    ON cr.customer_id = c.customer_id AND cr.snapshot_date = d.date_day
LEFT JOIN {{ ref('dim_customer_credit_history') }} h
    ON h.customer_id = c.customer_id
    AND d.date_day >= h.valid_from
    AND d.date_day < h.valid_to
    

