
SELECT
    id AS partner_id,
    name AS partner_name,
    TRY_CAST(ref AS INT) AS customer_id,
    NULLIF(LTRIM(RTRIM(vat)), '') AS tax_id,
    parent_id AS parent_partner_id,
    user_id AS owner_user_id,
    active AS is_active,
    write_date
FROM {{ source('bronze', 'crm_res_partner') }}