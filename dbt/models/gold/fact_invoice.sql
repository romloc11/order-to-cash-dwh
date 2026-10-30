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

with_lateness AS (
    SELECT
        *,
        -- días de atraso: pagada = clearing_date - due_date; abierta = fecha de corte - due_date.
        -- negativo = pagó antes de vencer (o aún no vence)
        CASE WHEN
            is_cleared = 1 THEN DATEDIFF(day, due_date, clearing_date)
            ELSE DATEDIFF(day, due_date, CAST('{{ var("as_of_date") }}' AS date))
        END AS days_late
    FROM with_dates
)

SELECT
    invoice_doc,
    billing_doc,
    customer_id,
    invoice_date,
    due_date,
    invoice_amount,
    currency,
    is_cleared,
    clearing_date,
    -- importe que sigue abierto
    CASE WHEN
        is_cleared = 0 THEN invoice_amount
        ELSE 0
    END AS open_amount,
    days_late,
    CASE
        WHEN is_cleared = 1 THEN 'cleared'
        WHEN days_late <= 0 THEN 'not_due'
        WHEN days_late BETWEEN 1 AND 15 THEN '1-15'
        WHEN days_late BETWEEN 16 AND 30 THEN '16-30'
        WHEN days_late BETWEEN 31 AND 60 THEN '31-60'
        ELSE '60+'
    END AS aging_bucket
FROM with_lateness
