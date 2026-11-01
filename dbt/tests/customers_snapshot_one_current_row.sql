SELECT
    customer_id,
    COUNT(*) AS current_versions
FROM {{ ref('customers_snapshot') }}
WHERE dbt_valid_to IS NULL
GROUP BY customer_id
HAVING COUNT(*) <> 1