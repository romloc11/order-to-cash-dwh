-- Employee names (PA0001). Used to turn the collector's employee number into a name.
select
    PERNR as employee_id,
    ENAME as employee_name
from {{ source('bronze', 'erp_pa0001') }}
