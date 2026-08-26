with source as (
    select * from {{ source('pipedrive', 'activity_types') }}
)

select
    id as activity_type_id,
    name as activity_name,
    lower(active) = 'yes' as is_active,
    type as activity_type_key
from source