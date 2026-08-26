with stage_changes as (

    select
        deal_id,
        change_time,
        new_value::int as stage_id

    from {{ ref('stg_pipedrive__deal_changes') }}
    where changed_field_key = 'stage_id'

),

first_entry as (

    select
        deal_id,
        stage_id,
        min(change_time) as entered_at

    from stage_changes
    group by deal_id, stage_id

)

select
    fe.deal_id,
    fe.stage_id,
    s.stage_name,
    fe.entered_at

from first_entry fe
inner join {{ ref('stg_pipedrive__stages') }} s
    on fe.stage_id = s.stage_id