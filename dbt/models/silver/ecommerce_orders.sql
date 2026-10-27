SELECT 
    id AS order_id,
    order_number,
    TRY_CAST(customer_ref AS INT) AS customer_id,
    created_at,
    status,
    total_amount,
    currency,
    updated_at
FROM {{ source('bronze', 'ecommerce_orders') }}
