WITH invoices AS (
    -- Facturas abiertas
    SELECT
        customer_id,
        document_number AS invoice_doc,
        billing_doc,
        document_date AS invoice_date,
        baseline_date,
        payment_days,
        amount AS invoice_amount,
        currency,
        CAST(NULL AS date) AS clearing_date
    FROM {{ ref('erp_open_items') }}
    WHERE document_type = 'RV'

    UNION ALL

    -- Facturas compensadas
    SELECT
        customer_id,
        document_number AS invoice_doc,
        billing_doc,
        document_date AS invoice_date,
        baseline_date,
        payment_days,
        amount AS invoice_amount,
        currency,
        clearing_date
    FROM {{ ref('erp_cleared_items') }}
    WHERE document_type = 'RV'
),

with_dates AS (
    SELECT 
        *,
        DATEADD(day, payment_days, baseline_date) AS due_date,
        CASE WHEN
            clearing_date IS NULL THEN 0 
            ELSE 1
        END AS is_cleared
    FROM invoices
),

pay_days AS (
    SELECT
        invoice_doc,
        MAX(application_date) AS paid_date
    FROM {{ ref('bridge_payment_application') }}
    WHERE application_type = 'payment'
    GROUP BY invoice_doc
),

with_lateness AS (
    SELECT
        wd.*,
        pd.paid_date,
        -- days late: cleared = paid_date - due_date; open = cut-off date - due_date.
        -- negative = paid before the due date (or not yet due)
        CASE WHEN
            wd.is_cleared = 1 THEN DATEDIFF(day, wd.due_date, pd.paid_date)
            ELSE DATEDIFF(day, wd.due_date, CAST('{{ var("as_of_date") }}' AS date))
        END AS days_late
    FROM with_dates wd
    LEFT JOIN pay_days pd ON pd.invoice_doc = wd.invoice_doc
)

SELECT
    i.invoice_doc,
    i.billing_doc,
    i.customer_id,
    i.invoice_date,
    i.due_date,
    i.invoice_amount,
    i.currency,
    i.is_cleared,
    i.clearing_date,
    i.paid_date,
    -- amount that is still open
    CASE WHEN
        i.is_cleared = 0 THEN i.invoice_amount
        ELSE 0
    END AS open_amount,
    i.days_late,
    CASE
        WHEN i.is_cleared = 1 THEN 'cleared'
        WHEN i.days_late <= 0 THEN 'not_due'
        WHEN i.days_late BETWEEN 1 AND 15 THEN '1-15'
        WHEN i.days_late BETWEEN 16 AND 30 THEN '16-30'
        WHEN i.days_late BETWEEN 31 AND 60 THEN '31-60'
        ELSE '60+'
    END AS aging_bucket
FROM with_lateness i
