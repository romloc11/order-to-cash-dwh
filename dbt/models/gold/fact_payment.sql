WITH payments AS (
    -- pagos abiertos
    SELECT
        document_number AS payment_doc,
        customer_id,
        posting_date AS payment_date,
        amount AS payment_amount,
        currency,
        0 AS is_cleared,
        CAST(NULL AS DATE) AS clearing_date
    FROM {{ ref('erp_open_items') }}
    WHERE document_type = 'DZ'

    UNION ALL

    -- pagos compensados
    SELECT
        document_number AS payment_doc,
        customer_id,
        posting_date AS payment_date,
        amount AS payment_amount,
        currency,
        1 AS is_cleared,
        clearing_date
    FROM {{ ref('erp_cleared_items') }}
    WHERE document_type = 'DZ'
)

SELECT * FROM payments