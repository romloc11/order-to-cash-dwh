-- Change log headers (CDHDR): who changed a customer, and when. One row per change.
-- CHAR columns arrive padded with spaces, so we rtrim them.
select
    rtrim(OBJECTCLAS) as object_class,
    try_cast(rtrim(OBJECTID) as int) as customer_id,
    CHANGENR as change_number,
    rtrim(USERNAME) as changed_by,
    try_convert(date, UDATE, 112) as change_date,
    UTIME as change_time,
    rtrim(TCODE) as transaction_code
from {{ source('bronze', 'erp_cdhdr') }}
