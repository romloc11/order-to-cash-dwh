-- Billing document headers (VBRK): one row per invoice issued.
select
    VBELN as billing_doc,
    FKART as billing_type,
    {{ sap_date('FKDAT') }} as billing_date,
    try_cast(KUNAG as int) as customer_id,
    NETWR as net_amount,
    WAERS as currency
from {{ source('bronze', 'erp_vbrk') }}
