
SELECT
    TRY_CAST(KUNNR AS INT) AS customer_id,
    NAME1 AS customer_name,
    {{ clean_text('STCD1') }} AS tax_id,
    KTOKD AS account_group,
    {{ sap_date('ERDAT') }} AS created_date
FROM {{ source('bronze', 'erp_kna1') }}