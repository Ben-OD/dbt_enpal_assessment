with stage_events as (

    select
        deal_id,
        stage_name                as kpi_name,
        cast(stage_id as varchar) as funnel_step,
        entered_at                as event_at

    from {{ ref('int_pipedrive__deal_stage_events') }}

),

call_events as (

    -- Sub-step assignment comes from the assessment brief, not from the
    -- source data: Sales Call 1 sits under step 2, Sales Call 2 under step 3.
    select
        deal_id,
        activity_name as kpi_name,
        case
            when activity_name = 'Sales Call 1' then '2.1'
            when activity_name = 'Sales Call 2' then '3.1'
        end           as funnel_step,
        called_at     as event_at

    from {{ ref('int_pipedrive__deal_call_events') }}

),

unioned as (

    select * from stage_events

    union all

    select * from call_events

)

select
    deal_id,
    kpi_name,
    funnel_step,
    event_at

from unioned