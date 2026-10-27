
SELECT 
    TRY_CAST(KUNNR AS INT) AS customer_id,
    KLIMK AS credit_limit,
    CASE WHEN
        CRBLB = 'X' THEN 1
        ELSE 0
    END AS is_credit_blocked,
    CTLPC AS risk_class
FROM {{ source('bronze', 'erp_knkk') }}