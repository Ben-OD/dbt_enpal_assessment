with source as (
    select * from {{ source('pipedrive', 'activity') }}
)

select
    activity_id,
    type as activity_type_key,
    assigned_to_user as user_id,
    deal_id,
    done as is_done,
    due_to as due_at
from source