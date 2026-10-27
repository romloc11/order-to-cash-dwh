-- Payment terms catalog (T052): how many days a customer has to pay.
select
    ZTERM as payment_terms_code,
    ZTAG1 as net_days,
    [TEXT] as description
from {{ source('bronze', 'erp_t052') }}
