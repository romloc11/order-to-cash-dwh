
SELECT
    TRY_CAST(KUNNR AS INT) AS customer_id,
    NAME1 AS customer_name,
    NULLIF(LTRIM(RTRIM(STCD1)), '') AS tax_id,
    KTOKD AS account_group,
    TRY_CONVERT(DATE, ERDAT, 112) AS created_date
FROM {{ source('bronze', 'erp_kna1') }}