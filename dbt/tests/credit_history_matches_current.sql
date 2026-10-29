{{ config(severity='warn') }}

SELECT 
    h.customer_id, 
    h.credit_limit AS history_limit, 
    c.credit_limit AS current_limit
FROM {{ ref('dim_customer_credit_history') }} h
JOIN {{ ref('erp_customer_credit') }} c ON c.customer_id = h.customer_id
WHERE h.is_current = 1
  AND h.credit_limit <> c.credit_limit