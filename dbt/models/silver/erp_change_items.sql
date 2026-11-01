-- Change log items (CDPOS): which field changed, from what value to what value.
-- Join to erp_change_headers on (customer_id, change_number) to get the date. That is Gold's job.
select
    rtrim(OBJECTCLAS) as object_class,
    try_cast(rtrim(OBJECTID) as int) as customer_id,
    CHANGENR as change_number,
    rtrim(TABNAME) as table_name,
    rtrim(FNAME) as field_name,
    CHNGIND as change_type,
    {{ clean_text('VALUE_OLD') }} as old_value,
    {{ clean_text('VALUE_NEW') }} as new_value
from {{ source('bronze', 'erp_cdpos') }}
