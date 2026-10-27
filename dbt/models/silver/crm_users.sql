-- CRM users (res.users): the people who own customers and log collection activities.
select
    id as user_id,
    login as user_login,
    name as user_name,
    active as is_active,
    create_date,
    write_date
from {{ source('bronze', 'crm_res_users') }}
