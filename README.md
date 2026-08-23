# Sales Funnel Analytics — Pipedrive

Solution to the Analytics Engineer take-home assessment. The original
brief is preserved below under **Assessment Brief**.

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

# 4. Install dbt
pip install dbt-core dbt-postgres

# 5. Verify the connection and build the models
dbt debug
dbt run
```

Results are written to the `public_pipedrive_analytics` schema. Connection
details are in `profiles.yml` (host `localhost`, port `5432`, user/password
`admin`).

Use `docker compose stop` rather than `down` between sessions — no volume is
mounted for the database, so `down` discards the loaded data and requires a
full reload on the next start.

### Note for Windows users

`.gitattributes` enforces LF line endings for `*.sh`. Without it, Git's
automatic CRLF conversion breaks `raw_data/load_data.sh` inside the Linux
container and the data load fails silently with a shell syntax error.

## Project structure

| Layer | Path | Materialization | Purpose |
| --- | --- | --- | --- |
| Staging | `models/staging/` | view | One model per source table; renaming and type casting only |
| Intermediate | `models/intermediate/` | view | Reusable transformation steps |
| Marts | `models/marts/` | table | Reporting models consumed downstream |

Source tables are declared in `models/sources.yml`. A flat layer structure was
chosen deliberately: the project has a single source system and a single
consuming domain, so the conventional `staging/<source>/` and
`marts/<domain>/` subdirectories would add nesting without adding meaning.
Source affiliation is carried in model names instead
(`stg_pipedrive__<entity>`).

## Modelling decisions

_To be completed._

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
