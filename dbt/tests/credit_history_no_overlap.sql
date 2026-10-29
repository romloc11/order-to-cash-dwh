SELECT a.customer_id, a.valid_from, a.valid_to, b.valid_from AS other_from, b.valid_to AS other_to
FROM {{ ref('dim_customer_credit_history') }} a
JOIN {{ ref('dim_customer_credit_history') }} b
    ON a.customer_id = b.customer_id
    AND a.valid_from < b.valid_from
    AND b.valid_from < a.valid_to