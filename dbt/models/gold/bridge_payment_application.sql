WITH groups AS (
    -- Step 1: for each clearing document, how many invoices and how many payments it contains
    SELECT
        clearing_document,
        SUM(CASE WHEN document_type = 'RV' THEN 1 ELSE 0 END) AS invoices,
        SUM(CASE WHEN document_type = 'DZ' THEN 1 ELSE 0 END) AS payments
    FROM {{ ref('erp_cleared_items') }}
    GROUP BY clearing_document
),

invoices AS (
    SELECT * FROM {{ ref('erp_cleared_items') }} WHERE document_type = 'RV'
),

payments AS (
    SELECT * FROM {{ ref('erp_cleared_items') }} WHERE document_type = 'DZ'
),

one_invoice AS (
    -- Rule 1: the group has a single invoice; the applied amount is the PAYMENT amount
    SELECT
        p.document_number AS application_doc,
        'payment' AS application_type,
        i.document_number AS invoice_doc,
        i.customer_id,
        p.posting_date AS application_date,
        p.amount AS allocated_amount,
        'one_invoice' AS application_rule
    FROM groups g
    JOIN payments p ON p.clearing_document = g.clearing_document
    JOIN invoices i ON i.clearing_document = g.clearing_document
    WHERE g.invoices = 1
),

one_payment AS (
    -- Rule 2: a single payment and several invoices; the applied amount is the INVOICE amount
    SELECT
        p.document_number AS application_doc,
        'payment' AS application_type,
        i.document_number AS invoice_doc,
        i.customer_id,
        p.posting_date AS application_date,
        i.amount AS allocated_amount,
        'one_payment' AS application_rule
    FROM groups g
    JOIN payments p ON p.clearing_document = g.clearing_document
    JOIN invoices i ON i.clearing_document = g.clearing_document
    WHERE g.invoices > 1 AND g.payments = 1
),

invoice_keys AS (
    -- Step for rule 3: the document number of every invoice, open or cleared,
    -- together with its billing document (billing_doc), which is what credit memos reference
    SELECT document_number AS invoice_doc, billing_doc
    FROM {{ ref('erp_open_items') }}
    WHERE document_type = 'RV'
    UNION ALL
    SELECT document_number AS invoice_doc, billing_doc
    FROM {{ ref('erp_cleared_items') }}
    WHERE document_type = 'RV'
),

credit_memos AS (
    -- Rule 3: each credit memo is applied to the invoice it references
    SELECT
        cm.credit_memo_doc AS application_doc,
        'credit_memo' AS application_type,
        k.invoice_doc,
        cm.customer_id,
        cm.credit_memo_date AS application_date,
        cm.credit_memo_amount AS allocated_amount,
        'credit_memo' AS application_rule
    FROM {{ ref('fact_credit_memo') }} cm
    JOIN invoice_keys k ON k.billing_doc = cm.billing_doc
),

multi_invoices AS (
    SELECT
        i.clearing_document,
        i.document_number AS invoice_doc,
        i.customer_id,
        i.amount,
        SUM(i.amount) OVER (
            PARTITION BY i.clearing_document
            ORDER BY DATEADD(day, i.payment_days, i.baseline_date), i.document_number
            ROWS UNBOUNDED PRECEDING
        ) AS end_amount
    FROM groups g
    JOIN invoices i ON i.clearing_document = g.clearing_document
    WHERE g.invoices > 1 AND g.payments > 1
),

multi_payments AS (
    SELECT
        p.clearing_document,
        p.document_number AS payment_doc,
        p.posting_date,
        p.amount,
        SUM(p.amount) OVER (
            PARTITION BY p.clearing_document
            ORDER BY p.posting_date, p.document_number
            ROWS UNBOUNDED PRECEDING
        ) AS end_amount
    FROM groups g
    JOIN payments p ON p.clearing_document = g.clearing_document
    WHERE g.invoices > 1 AND g.payments > 1
),

waterfall_raw AS (
    SELECT
        mp.payment_doc AS application_doc,
        'payment' AS application_type,
        mi.invoice_doc,
        mi.customer_id,
        mp.posting_date AS application_date,
        LEAST(mi.end_amount, mp.end_amount)
            - GREATEST(mi.end_amount - mi.amount, mp.end_amount - mp.amount) AS allocated_amount,
        'waterfall' AS application_rule
    FROM multi_invoices mi
    JOIN multi_payments mp ON mp.clearing_document = mi.clearing_document
),

waterfall AS (
    SELECT * FROM waterfall_raw WHERE allocated_amount > 0
)



SELECT * FROM one_invoice
UNION ALL
SELECT * FROM one_payment
UNION ALL
SELECT * FROM credit_memos
UNION ALL
SELECT * FROM waterfall