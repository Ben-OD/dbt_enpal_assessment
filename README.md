# Sales Funnel Analytics — Pipedrive

Solution to the Analytics Engineer take-home assessment. The original brief is
preserved below under **Assessment Brief**.

The deliverable is a single reporting model, `rep_sales_funnel_monthly`, built
on a staging → intermediate → marts layer structure with dbt.

## Prerequisites

- Docker Desktop (WSL 2 backend on Windows)
- Python 3.12
- Git

## Setup

```bash
# 1. Start Postgres and load the raw CSV data
docker compose up -d

# 2. Verify the loader finished successfully
docker compose logs data_loader

# 3. Create an isolated Python environment
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1        # Windows
# source .venv/bin/activate         # macOS / Linux

# 4. Install dbt and package dependencies
pip install dbt-core dbt-postgres
dbt deps

# 5. Verify the connection, then build and test everything
dbt debug
dbt build
```

`dbt build` loads the seed, runs all ten models and executes 53 tests — 64 nodes
in total. Results are written to the `public_pipedrive_analytics` schema;
connection details are in `profiles.yml` (host `localhost`, port `5432`,
user/password `admin`).

Use `docker compose stop` rather than `down` between sessions. No volume is
mounted for the database, so `down` discards the loaded data and forces a full
reload on the next start.

### Note for Windows users

`.gitattributes` enforces LF line endings for `*.sh`. Without it, Git's
automatic CRLF conversion breaks `raw_data/load_data.sh` inside the Linux
container: the loader fails with a shell syntax error while `init.sql` still
succeeds, leaving empty tables and no obvious cause.

## Project structure

| Layer | Path | Materialization | Purpose |
| --- | --- | --- | --- |
| Staging | `models/staging/` | view | One model per source table; renaming and type casting only |
| Intermediate | `models/intermediate/` | view | Event extraction and unification |
| Marts | `models/marts/` | table | Reporting model |
| Seeds | `seeds/` | table | Reference list of funnel steps |

```
stg_pipedrive__deal_changes  ─┐
stg_pipedrive__stages        ─┴─→ int_pipedrive__deal_stage_events  ─┐
                                                                     ├─→ int_pipedrive__funnel_events ─┐
stg_pipedrive__activity      ─┐                                      │                                 ├─→ rep_sales_funnel_monthly
stg_pipedrive__activity_types─┴─→ int_pipedrive__deal_call_events   ─┘                                 │
                                                                       funnel_steps (seed) ────────────┘
```

A flat layer structure was chosen deliberately. The project has a single source
system and a single consuming domain, so the conventional `staging/<source>/`
and `marts/<domain>/` subdirectories would add nesting without adding meaning.
Source affiliation is carried in model names instead (`stg_pipedrive__<entity>`).

`stg_pipedrive__users` and `stg_pipedrive__fields` are not consumed downstream.
They are included because the staging layer should represent the source
completely; `fields` in particular documents the label mappings for dropdown
fields, which was needed during exploration.

### Naming conventions

- `stg_<source>__<entity>` for staging, `int_<source>__<concept>` for
  intermediate, `rep_<subject>` for reporting models
- Booleans prefixed `is_`, timestamps suffixed `_at`
- Generic source keys renamed to their entity (`id` → `activity_type_id`)
- The dbt source is named `pipedrive` rather than `postgres_public`: it
  describes the system of record, not the storage location

## Understanding the source data

### Structure

`deal_changes` is an entity-attribute-value table: one row per changed field,
with `deal_id` as the entity, `changed_field_key` as the attribute and
`new_value` as an untyped text value. Only four field keys occur — `stage_id`
(8,906 rows), `user_id` (2,500), `add_time` (2,000) and `lost_reason` (2,000) —
and an `accepted_values` test guards that assumption.

Because the type of `new_value` depends on the field key in the same row, no
casting happens in staging. It is deferred to the intermediate layer, where the
filter on `changed_field_key` makes the type unambiguous.

The data covers 2,000 deal creations across 1,995 distinct IDs. Every deal has
a `stage_id = 1` entry, so step 1 is derived from the stage history rather than
from `add_time`.

Deals skip stages freely (e.g. deal 881836 goes 1 → 2 → 3 → 4 → 6), and 15
deal-stage combinations occur more than once, i.e. deals occasionally re-enter a
stage they have already passed.

### Data quality observations

**The dataset is synthetic.** All changes belonging to one deal share an
identical time-of-day, with only the date varying (deal 881836: every change at
21:32:09, deal 709537: every change at 12:15:23). Stage skips and re-entries are
therefore artefacts of generation, not business behaviour, and should not be
interpreted as process signal.

**`activity_id` is not a key.** 4,579 rows contain only 4,568 distinct values.
No uniqueness test is placed on it; the intermediate layer deduplicates by deal
and call type instead.

**`is_done` contains NULLs.** These are excluded by the `is_done = true` filter
along with the explicit `false` values.

**The observation windows differ.** `deal_changes` runs from 2024-01-01 to
2025-03-11, while `activity.due_to` ends on 2024-09-13. The last months of the
report therefore contain stage events but no call events.

### The sub-step hierarchy does not hold in the data

The brief places Sales Call 1 under step 2 and Sales Call 2 under step 3,
implying that a call belongs to the deal's qualification or needs-assessment
phase. That relationship does not exist in this dataset.

| Set | Distinct deals |
| --- | --- |
| Deals with any activity | 4,572 |
| Deals with a stage history | 1,995 |
| Intersection | 8 |

Both tables draw `deal_id` from the same range (roughly 100,000–999,999). If the
IDs were drawn independently from ~900,000 possible values, the expected overlap
would be `4,572 × 1,995 / 900,000 ≈ 10` — which is what we observe. The two
tables were generated independently, without reconciling deal identifiers.

After filtering to completed Sales Call 1 and 2 activities, 1,128 deals remain,
of which 567 of the 568 with a Sales Call 1 never reached stage 2.

**Consequence:** steps 2.1 and 3.1 must be read as standalone activity metrics,
not as subsets of the step above them. A funnel chart rendering them as a branch
of steps 2 and 3 would imply a relationship the data does not support. The model
still emits the numbering as specified, because it is a requirement of the brief.

### Lookup values

`fields.field_value_options` (JSONB) holds the label mapping for dropdown
fields. `lost_reason` resolves to: 1 = Customer Not Ready, 2 = Pricing Issues,
3 = Unreachable Customer, 4 = Product Mismatch, 5 = Duplicate Entry. The field
is populated for all 2,000 deals but is not part of the required output, so it
is not modelled beyond staging.

Note that activity types join on the `type` column, not on `id`, and that the
key for Sales Call 1 is `meeting` — not `sc_1`, as the parallel `sc_2` would
suggest. Filtering happens on `activity_name` rather than the key to avoid
relying on that inconsistency.

## Modelling decisions

**`deals_count` counts first arrivals.** A deal contributes to a step in the
month it first reached that step. This is the standard funnel reading and is
applied consistently to stages and calls. The alternatives — deals *in* a step
at month end, or a cumulative count — would answer different questions and are
not what "funnel steps" implies. Choosing the first arrival also keeps past
periods immutable: a later re-entry never changes an already reported month,
which a last-arrival reading would.

**Re-entries collapse to the earliest occurrence.** Where a deal enters a stage
more than once, only the first entry counts. The opposite reading is defensible
(a re-entry could mean the first pass was invalid), but "reached" is a
one-directional property, and with 15 affected combinations out of ~8,900 the
choice barely moves the numbers.

**Only completed calls count.** A planned but unfinished activity is a scheduled
appointment, not a funnel step reached. Filtering on `is_done = true` also avoids
generating rows for future months from open activities with future due dates.

**`due_at` is used as the event timestamp.** The source has no creation or
completion date for activities, only a due date. For completed activities it is
the closest available proxy; this is a limitation of the source, not a modelling
preference.

**Deal owner is ignored.** `user_id` changes during a deal's lifetime (1,494
deals have one change, 497 have two, 4 have three), and the required output has
no owner dimension. Attributing a deal to a single owner would require an
arbitrary rule with no benefit here.

**`kpi_name` follows the source spelling.** `stages.stage_name` contains
"Qualified lead" in lower case, while both the brief and
`fields.field_value_options` capitalise it. `stages` is the dedicated table for
stage master data, whereas `fields` carries the label as part of a
field-configuration blob; where they disagree, the dedicated table wins. This is
the one place where the output deviates cosmetically from the brief.

**`funnel_step` is text.** The sub-steps 2.1 and 3.1 rule out an integer, and the
brief fixes the output at four columns, ruling out a split into major/minor
columns. A numeric type would work mechanically but misrepresents the column:
`funnel_step` is an identifier, not a quantity — 2.1 denotes the first sub-step
of step 2, not the value two point one. Sorting is therefore handled by an
explicit `step_order` column in the `funnel_steps` seed rather than by the text
value, which would place '10' directly after '1' should the funnel ever exceed
nine main steps.

**Both axes of the report are complete.** The month range is not hard-coded: the
model queries the actual bounds of `event_at` at compile time via `run_query` and
feeds them into `dbt_utils.date_spine`. That spine is crossed with the full step
list from the `funnel_steps` seed, so every month × step combination exists.
Months in which a step saw no arrivals appear with `deals_count = 0` instead of
being absent, and a step no deal ever reached would still be present in every
month rather than vanishing from the report. Downstream charts get a continuous
series without having to reconstruct missing rows.

**The seed defines the steps, the data defines the labels.** `funnel_steps.csv`
holds the eleven steps required by the brief with their numbering and sort order.
`kpi_name`, however, is taken from the observed events wherever they exist; the
seed's label serves only as a fallback for steps with no data. This keeps the
step list authoritative without overriding the source spelling decision above.

## How to read the report

Each row answers: *how many deals reached this step for the first time during
this month?*

The numbers within a single month are **not** monotonically decreasing, and that
is expected. A deal reaching step 3 in October passed step 1 months earlier, so
every month mixes cohorts. In October 2024, 119 deals reached Lead Generation
while 137 reached Needs Assessment — different deals at different points in their
lifecycle. The funnel shape is visible in the totals across the whole period
(1,995 → 1,479 → 1,305 → 1,086 → 894 → 741 → 588 → 479 → 324), not within a
month.

Two edge effects follow from the observation window. In January 2024 the later
steps are still empty because no deal has had time to reach them, and from
October 2024 onwards the sales-call rows are zero because activity data ends in
September. From December 2024, lead generation stops while later stages still
show movement — the final cohorts working their way through.

## Testing

53 tests run as part of `dbt build`:

- `not_null` and `unique` on all keys, `relationships` on every foreign key
- `relationships` from `int_pipedrive__funnel_events.funnel_step` to the
  `funnel_steps` seed, so a step present in the data but missing from the
  reference list fails the build
- `accepted_values` on `changed_field_key`, `activity_name` and `funnel_step` —
  these encode assumptions from exploration and will fail loudly if the source
  gains an unexpected value
- `dbt_utils.unique_combination_of_columns` on every model's grain: deal + stage,
  deal + call type, deal + funnel step, month + funnel step
- `dbt_utils.accepted_range` on `deals_count`

The grain tests are the important ones. Each intermediate model promises exactly
one row per deal and step; if that promise broke, the report would silently
double-count.

## Known limitations and next steps

- `due_at` stands in for an actual call timestamp; a source with completion
  dates would remove that approximation
- No conversion rates between steps are calculated. With the cohort mixing
  described above, a meaningful conversion metric would need cohort-based
  modelling (deals grouped by entry month, tracked forward), which the requested
  output shape does not accommodate
- The funnel definition lives centrally in the mart rather than being
  reimplemented per dashboard. Promoting it into a semantic layer would be the
  natural next step in a production setup

---

# Assessment Brief

## Setup

1. Download Docker Desktop (if you don’t have installed) using the official website, install and launch.
2. Fork this Github project to you Github account. Clone the forked repo to your device.
3. Open your Command Prompt or Terminal, navigate to that folder, and run the command `docker compose up`.
4. Now you have launched a local Postgres database with the following credentials:
 ```
    Host: localhost
    User: admin
    Password: admin
    Port: 5432 
```
5. Connect to the db via a preferred tool (e.g. DataGrip, Dbeaver etc)
6. Install dbt-core and dbt-postgres using pip (if you don’t have) on your preferred environment.
7. Now you can run `dbt run` with the test model and check public_pipedrive_analytics schema to see the dbt result (with one test model)

## Project
1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (rep_sales_funnel_monthly) with monthly intervals, incorporating the following funnel steps (KPIs):  
  &nbsp;&nbsp;&nbsp;Step 1: Lead Generation  
  &nbsp;&nbsp;&nbsp;Step 2: Qualified Lead  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 2.1: Sales Call 1  
  &nbsp;&nbsp;&nbsp;Step 3: Needs Assessment  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 3.1: Sales Call 2  
  &nbsp;&nbsp;&nbsp;Step 4: Proposal/Quote Preparation  
  &nbsp;&nbsp;&nbsp;Step 5: Negotiation  
  &nbsp;&nbsp;&nbsp;Step 6: Closing  
  &nbsp;&nbsp;&nbsp;Step 7: Implementation/Onboarding  
  &nbsp;&nbsp;&nbsp;Step 8: Follow-up/Customer Success  
  &nbsp;&nbsp;&nbsp;Step 9: Renewal/Expansion
5. Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
6. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.
