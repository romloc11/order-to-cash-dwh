WITH credit_memo AS (
    SELECT
        document_number AS credit_memo_doc,
        reference AS billing_doc,
        customer_id,
        posting_date AS credit_memo_date,
        amount AS credit_memo_amount,
        currency,
        0 AS is_cleared,
        CAST(NULL AS DATE) AS clearing_date
    FROM {{ ref('erp_open_items') }}
    WHERE document_type = 'DG'

    UNION ALL

    SELECT
        document_number AS credit_memo_doc,
        reference AS billing_doc,
        customer_id,
        posting_date AS credit_memo_date,
        amount AS credit_memo_amount,
        currency,
        1 AS is_cleared,
        clearing_date
    FROM {{ ref('erp_cleared_items') }}
    WHERE document_type = 'DG'
)

SELECT * FROM credit_memo
