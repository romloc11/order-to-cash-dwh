SELECT f.total AS fact_total, b.total AS billing_total
FROM (SELECT SUM(invoice_amount) AS total FROM {{ ref('fact_invoice') }}) f
CROSS JOIN (SELECT SUM(net_amount) AS total FROM {{ ref('erp_billing') }}) b
WHERE f.total <> b.total