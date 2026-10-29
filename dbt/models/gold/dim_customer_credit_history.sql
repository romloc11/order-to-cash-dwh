WITH changes AS (
    -- Paso 1: un renglón por cambio de límite, ya con fecha y valores numéricos
    SELECT
        h.customer_id,
        h.change_date,
        TRY_CAST(i.old_value AS DECIMAL(15,2)) AS old_limit,
        TRY_CAST(i.new_value AS DECIMAL(15,2)) AS new_limit,
        ROW_NUMBER() OVER (PARTITION BY h.customer_id ORDER BY h.change_date, h.change_number) AS rn
    FROM {{ ref('erp_change_headers') }} h
    JOIN {{ ref('erp_change_items') }} i
        ON i.customer_id = h.customer_id
        AND i.change_number = h.change_number
    WHERE i.table_name = 'KNKK' AND i.field_name = 'KLIMK'
),

initial_version AS (
    -- Paso 2: la versión que existía ANTES del primer cambio
    SELECT
        customer_id,
        old_limit AS credit_limit,
        CAST('1900-01-01' AS date) AS valid_from,
        change_date AS valid_to
    FROM changes
    WHERE rn = 1
),

change_versions AS (
    -- Paso 3: la versión que empieza en cada cambio
    SELECT
        customer_id,
        new_limit AS credit_limit,
        change_date AS valid_from,
        LEAD(change_date, 1, CAST('9999-12-31' AS date))
            OVER (PARTITION BY customer_id ORDER BY rn) AS valid_to
    FROM changes
),

never_changed AS (
    -- Paso 4: clientes sin cambios en la bitácora: una sola versión, su límite actual
    SELECT
        customer_id,
        credit_limit,
        CAST('1900-01-01' AS date) AS valid_from,
        CAST('9999-12-31' AS date) AS valid_to
    FROM {{ ref('erp_customer_credit') }}
    WHERE customer_id NOT IN (SELECT customer_id FROM changes)
),

all_versions AS (
    SELECT * FROM initial_version
    UNION ALL
    SELECT * FROM change_versions
    UNION ALL
    SELECT * FROM never_changed
)

SELECT
    customer_id,
    credit_limit,
    valid_from,
    valid_to,
    CASE WHEN valid_to = '9999-12-31' THEN 1 ELSE 0 END AS is_current
FROM all_versions