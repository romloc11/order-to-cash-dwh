select
    try_cast(KUNNR as int) as customer_id,
    NAME1 as customer_name,
    nullif(ltrim(rtrim(STCD1)), '') as tax_id,
    KTOKD as account_group,
    try_convert(date, ERDAT, 112) as created_date
from {{ source('bronze', 'erp_kna1') }}