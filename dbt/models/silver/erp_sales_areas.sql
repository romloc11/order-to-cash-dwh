-- One row per customer x sales area (KNVV). A customer can sell in several areas.
select
    try_cast(KUNNR as int) as customer_id,
    VKORG as sales_org,
    VTWEG as distribution_channel,
    SPART as division,
    BZIRK as district_code,
    ZTERM as payment_terms_code
from {{ source('bronze', 'erp_knvv') }}
