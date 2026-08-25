with call_activities as (

    select
        a.deal_id,
        t.activity_name,
        a.due_at

    from {{ ref('stg_pipedrive__activity') }} a
    inner join {{ ref('stg_pipedrive__activity_types') }} t
        on a.activity_type_key = t.activity_type_key

    where a.is_done = true
      and t.activity_name in ('Sales Call 1', 'Sales Call 2')

),

first_call as (

    select
        deal_id,
        activity_name,
        min(due_at) as called_at

    from call_activities
    group by deal_id, activity_name

)

select
    deal_id,
    activity_name,
    called_at

from first_call