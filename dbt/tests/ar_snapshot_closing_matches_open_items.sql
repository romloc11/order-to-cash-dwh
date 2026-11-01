SELECT s.closing_balance, o.open_balance
FROM (
    SELECT SUM(net_balance) AS closing_balance
    FROM {{ ref('fact_ar_snapshot') }}
    WHERE snapshot_date = CAST('{{ var("as_of_date") }}' AS date)
) s
CROSS JOIN (
    SELECT
        SUM(CASE WHEN document_type = 'RV' THEN amount ELSE -amount END) AS open_balance
    FROM {{ ref('erp_open_items') }}
) o
WHERE s.closing_balance <> o.open_balance

