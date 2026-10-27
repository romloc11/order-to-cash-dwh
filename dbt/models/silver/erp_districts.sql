-- Sales district catalog (T171T).
select
    BZIRK as district_code,
    BZTXT as district_name
from {{ source('bronze', 'erp_t171t') }}
