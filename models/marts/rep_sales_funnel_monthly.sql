{% set bounds_query %}
    select
        to_char(date_trunc('month', min(event_at)), 'YYYY-MM-DD') as start_month,
        to_char(date_trunc('month', max(event_at)) + interval '1 month', 'YYYY-MM-DD') as end_month
    from {{ ref('int_pipedrive__funnel_events') }}
{% endset %}

{% if execute %}
    {% set bounds = run_query(bounds_query).rows[0] %}
    {% set start_month = bounds[0] %}
    {% set end_month = bounds[1] %}
{% else %}
    {% set start_month = '2024-01-01' %}
    {% set end_month = '2024-02-01' %}
{% endif %}

with months as (

    {{ dbt_utils.date_spine(
        datepart="month",
        start_date="cast('" ~ start_month ~ "' as date)",
        end_date="cast('" ~ end_month ~ "' as date)"
    ) }}

),

observed_labels as (

    select distinct
        funnel_step,
        kpi_name
    from {{ ref('int_pipedrive__funnel_events') }}

),

scaffold as (

    select
        cast(m.date_month as date)          as month,
        fs.funnel_step,
        coalesce(ol.kpi_name, fs.kpi_name)  as kpi_name,
        fs.step_order
    from months m
    cross join {{ ref('funnel_steps') }} fs
    left join observed_labels ol
        on fs.funnel_step = ol.funnel_step

),

events_by_month as (

    select
        cast(date_trunc('month', event_at) as date) as month,
        funnel_step,
        count(distinct deal_id) as deals_count
    from {{ ref('int_pipedrive__funnel_events') }}
    group by 1, 2

)

select
    s.month,
    s.kpi_name,
    s.funnel_step,
    coalesce(e.deals_count, 0) as deals_count

from scaffold s
left join events_by_month e
    on  s.month = e.month
    and s.funnel_step = e.funnel_step

order by s.month, s.step_order