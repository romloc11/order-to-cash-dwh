-- Order holds: one row each time an order was put on hold.
-- released_at NULL means the hold is still active.
select
    id as hold_id,
    order_id,
    reason as hold_reason,
    held_at,
    released_at,
    release_type,
    updated_at
from {{ source('bronze', 'ecommerce_order_holds') }}
