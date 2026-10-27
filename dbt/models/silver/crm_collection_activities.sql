-- Collection activities logged in the CRM: calls, emails, promises to pay.
select
    id as activity_id,
    partner_id,
    nullif(ltrim(rtrim(invoice_ref)), '') as invoice_ref,
    activity_type,
    outcome,
    promised_date,
    promised_amount,
    note,
    user_id,
    create_date,
    write_date
from {{ source('bronze', 'crm_collection_activity') }}
