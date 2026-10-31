SELECT f.invoice_doc, f.invoice_amount, ISNULL(a.applied_amount, 0) AS applied_amount
FROM {{ ref('fact_invoice') }} f
LEFT JOIN (
    SELECT invoice_doc, SUM(allocated_amount) AS applied_amount
    FROM {{ ref('bridge_payment_application') }}
    GROUP BY invoice_doc
) a ON a.invoice_doc = f.invoice_doc
WHERE f.is_cleared = 1
  AND f.invoice_amount <> ISNULL(a.applied_amount, 0)
