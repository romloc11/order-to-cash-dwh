-- Partner functions per customer (KNVP). PARVW 'CO' = collector (the person who chases payment).
select
    try_cast(KUNNR as int) as customer_id,
    VKORG as sales_org,
    VTWEG as distribution_channel,
    SPART as division,
    PARVW as partner_function,
    PARZA as partner_counter,
    PERNR as employee_id
from {{ source('bronze', 'erp_knvp') }}
