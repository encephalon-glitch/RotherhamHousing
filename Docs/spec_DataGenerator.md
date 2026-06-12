# spec_DataGenerator.md

## Overview

`generate_data.py` is the synthetic data generator for the `RotherhamHousingRepairs` database.
It is not a utility script -- it is a documented data pipeline with external dependencies,
embedded business logic, and deliberate design decisions. This spec records what it does,
why it does it that way, and what was consciously left out.

All data produced is intentionally synthetic. See `DISCLAIMER.md`.

---

## Version History

| Version | Changes |
|---------|---------|
| v1.3 | Date range extended to two financial years (2024/25 and 2025/26). Job count scaled to 2,000. GOV.UK bank holiday fetch added -- IsWorkingDay correctly populated including bank holidays. Date-aware status logic -- In Progress restricted to jobs raised within IN_PROGRESS_WINDOW_DAYS of dataset end. Property type weighting revised against Rotherham MBC stock profile and English Housing Survey 2024. Bedroom and EPC distributions made property-type-aware. |
| v1.2 | Ward list replaced with 25 real Rotherham MBC ward names. Connection string SERVER replaced with placeholder for portability. |
| v1.1 | Urgent priority band added. No Access status added. Awaab's Law three-tier RAG alignment. |
| v1.0 | Initial generator. Calendar, Properties, RepairJobs. Single financial year. |

---

## Dependencies

### Python Libraries

| Library | Purpose |
|---------|---------|
| `pyodbc` | SQL Server connection and cursor execution |
| `pandas` | Dataframe operations (diagnostic use) |
| `faker` | Locale-aware synthetic data generation (en_GB) |
| `random` | Weighted random selection throughout |
| `datetime` | Date arithmetic across calendar and job generation |
| `requests` | GOV.UK bank holiday JSON fetch (v1.3) |
| `json` | Bank holiday response parsing (v1.3) |

### External Endpoints

| Endpoint | Purpose | Consumer |
|----------|---------|---------|
| `https://www.gov.uk/bank-holidays.json` | England and Wales bank holiday dates | Calendar population (v1.3) |

### Database

- SQL Server LocalDB instance (`(localdb)\<YourServer>`)
- Database: `RotherhamHousingRepairs`
- Windows authentication (Trusted_Connection)
- ODBC Driver 17 for SQL Server required

---

## Architecture Decisions

### Staging Layer

Repair jobs are inserted into `RepairJobs_Staging` before promotion to `RepairJobs`.
The staging layer exists to catch malformed rows -- NULL property references,
unrecognised priority or status values -- before they reach the clean fact table.
The validation filter on the INSERT...SELECT is the quality gate.

### Constants Block

All configurable values declared as named constants at module level before any
execution code. Nothing hardcoded in the loops. Any policy change -- job count,
date range, status window, property weights -- requires a single edit in one place.

### Random Seed

`random.seed(42)` is set at module level. Reproducible output on every run
against an empty database. Removing or changing the seed will alter all
generated values.

### Placeholder Connection String

The SERVER value uses `<YourServer>` as a placeholder. This is intentional --
real instance names must never appear in version-controlled code.
Run `sqllocaldb info` to list available instances.

### Insert Not Upsert

The generator inserts. It does not check for existing rows. Running against
a populated database will produce duplicates. Truncate or rebuild before
regenerating -- see Regeneration Instructions below.

---

## Bank Holiday Fetch

`fetch_bank_holidays(url, division, date_from, date_to)` is called once at
startup. The result is a `set` of `date` objects passed into the calendar loop
-- not fetched per row.

- Division: `england-and-wales`
- Dates parsed and filtered to the target date range
- Set lookup is O(1) -- no performance impact in the calendar loop
- Error handling covers: timeout, HTTP error, connection failure, missing division
- All failure paths raise `SystemExit` with a diagnostic message
- Available divisions printed if the expected division is missing

This brings `IsWorkingDay` into alignment with the Power BI reporting calendar,
which draws from the same GOV.UK endpoint. Same authoritative source, two
consumers -- consistent working day definition across the SQL and BI layers.

---

## Calendar Population

Date range: two financial years, 2024/25 and 2025/26 (v1.3).

`IsWorkingDay` set to 1 where the date is a weekday AND not in the bank
holiday set. Set to 0 for weekends or bank holidays.

Extended from one year to support cross-period trend visuals in Power BI
and to produce natural repeat repair collisions for window function demo.
One year looked like a pilot; two years presents as a live system.

### Financial Year Logic

April start. `financial_year()` returns strings in the format `2024/25`.
Fiscal year boundary handled by month comparison -- no hardcoded year values.

---

## Properties

500 synthetic properties seeded with:

- Sequential reference: `PROP0001` to `PROP0500`
- wardID: randomly selected from 1 to 25 (v1.2)
- Property type: House (55%), Flat (35%), Bungalow (10%)
- Bedrooms: property-type-aware distribution (v1.3)
- EPC rating: property-type-aware distribution (v1.3)
- Build year: 1920-2020 uniform
- Decent homes flag: properties rated D or E have a 30% chance of being marked non-decent

### Property Type Weighting

Revised in v1.3 against Rotherham MBC housing stock profile and English
Housing Survey 2024 data. Original weighting (House 60%, Flat 25%, Bungalow 15%)
was not supported by evidence. Rotherham is described as largely semi-detached
house stock; nationally, flats account for approximately 45% of social rented
dwellings. Bungalow reduced significantly -- 15% had no evidential basis.

| Type | Weight | Basis |
|------|--------|-------|
| House | 55% | Rotherham house-heavy stock profile |
| Flat | 35% | National social housing flat prevalence |
| Bungalow | 10% | Small but present; older and specialist stock |

### Bedroom Distribution

Property-type-aware from v1.3. Previous assignment was independent of
property type -- 4-bed flats and 4-bed bungalows were possible. Both are
implausible in social housing stock.

| Type | 1-bed | 2-bed | 3-bed | 4-bed |
|------|-------|-------|-------|-------|
| House | 5% | 25% | 55% | 15% |
| Flat | 45% | 50% | 5% | 0% |
| Bungalow | 50% | 45% | 5% | 0% |

### EPC Distribution

Property-type-aware from v1.3. Previous assignment was independent of
property type -- A-rated bungalows and E-rated new flats were possible.

Bungalows weighted toward D/E: single storey, high roof-to-floor heat loss
ratio, predominantly older builds. Flats weighted toward C and above: shared
walls, smaller floor area, more likely retrofitted.

| Type | A | B | C | D | E |
|------|---|---|---|---|---|
| House | 2% | 8% | 45% | 32% | 13% |
| Flat | 3% | 15% | 55% | 22% | 5% |
| Bungalow | 1% | 4% | 35% | 40% | 20% |

Ward names are real Rotherham MBC ward names as of the 2024 boundary review.
Power BI map geocoding requires real place names -- synthetic names produce
NULL coordinates and break geo visuals.

---

## Repair Jobs

### Volume

- v1.3: 2,000 jobs, two financial years -- same density as v1.2, extended range
- v1.2: 1,000 jobs, one financial year

Two years chosen to produce natural repeat repair collisions for window
function demo, support cross-period trend visuals, and present as a
credible live system rather than a pilot dataset.

### Priority Distribution

| Priority | Weight | Basis |
|----------|--------|-------|
| Emergency | 15% | Rotherham published KPI profile |
| Urgent | 14% | Awaab's Law three-tier alignment (v1.1) |
| Non-Emergency | 71% | Rotherham published KPI profile |

### Status Distribution

Date-aware from v1.3. `In Progress` is only assigned to jobs raised within
`IN_PROGRESS_WINDOW_DAYS` of the dataset end date. Jobs older than the cutoff
receive terminal statuses only. A job raised 18 months ago still showing as
In Progress is not credible in a two-year dataset.

```
IN_PROGRESS_WINDOW_DAYS = 90
in_progress_cutoff = END_DATE - timedelta(days=IN_PROGRESS_WINDOW_DAYS)
```

| Cohort | Statuses Available | Weights |
|--------|-------------------|---------|
| Raised before cutoff | Completed, Cancelled, No Access | 91%, 5%, 4% |
| Raised after cutoff | Completed, In Progress, Cancelled, No Access | 85%, 8%, 4%, 3% |

Validated in diagnostic: 26 In Progress from approximately 225 recent jobs.

### Contractor Assignment

| Priority | Contractors | Split |
|----------|-------------|-------|
| Emergency | Mears (1), Direct Works (3) | 60/40 |
| Urgent / Non-Emergency | Mears (1), Equans (2) | 50/50 |

Contractor IDs are integer keys -- not name strings -- to avoid fragile
string matching downstream.

### Category Weighting

Category 1 (Damp/Mould) is weighted toward winter months (November-March)
to reflect seasonal demand. All other categories use a flatter distribution.

Winter weights: `[20, 10, 15, 10, 8, 5, 8, 8, 6, 4, 4, 2]`
Summer weights: `[8, 5, 10, 8, 10, 8, 12, 12, 10, 8, 6, 3]`

### Completion Times

| Priority | Target | On-Target Rate | Breach Range |
|----------|--------|---------------|--------------|
| Emergency | 1 calendar day | 99% | 2-5 days |
| Urgent | 14 days (Awaab's Law) | 92% | 15-30 days |
| Non-Emergency | 20 days | 98% | 21-40 days |

### Right First Time

95.7% -- sourced from Rotherham published performance figures.
Only populated for Completed jobs. NULL for all other statuses.

### Tenant Satisfaction

Score 1-5, weighted toward 4-5 to reflect typical social housing survey
response patterns. Only populated for Completed jobs.

---

## Staging to Fact Promotion

Validation filter on INSERT...SELECT:

- `PropertyRef IS NOT NULL`
- `CategoryID IS NOT NULL`
- `Priority IN ('Emergency', 'Urgent', 'Non-Emergency')`
- `Status IN ('Completed', 'In Progress', 'Cancelled', 'No Access')`

Rows failing validation remain in staging and are not promoted.
Staging is not truncated post-load -- supports audit inspection.

---

## Diagnostic Output

Expected output on a clean run:

```
Fetching bank holidays from https://www.gov.uk/bank-holidays.json...
  HTTP 200 -- fetch successful.
  15 bank holidays loaded within target range.
Generating Calendar...
  730 calendar rows inserted.
Generating Properties...
  500 properties inserted.
Generating Repair Jobs...
  2000 staging rows inserted.
Loading RepairJobs from staging...
  2000 rows loaded into RepairJobs.

Done. Database populated.
```

Counts should be verified against expected values before proceeding.
A mismatch between staging and fact counts indicates validation rejections
and warrants inspection of the staging table.

---

## Known Limitations and Conscious Omissions

### Calendar Days vs Working Days

`DaysToComplete` in the generator is raw calendar days throughout.
The Power BI reporting calendar implements working day logic correctly.
Non-Emergency SLA targets (20 days) are almost certainly working-day based
in production. Closing this gap requires `fn_WorkingDaysBetween`, planned
once `IsWorkingDay` is fully validated. See also `spec_GetContractorPerformance.md`.

### EPC and Build Year Correlation

EPC rating and build year are correlated in the real world -- pre-1960
properties are overwhelmingly D or E without major retrofit. This
relationship is not modelled. Build year and EPC are assigned independently.
Modelling the correlation adds significant complexity for marginal demo value.

### No Audit Table

A production implementation would include an audit table capturing insert
events -- timestamp, operation, row count, source. The generator's diagnostic
print statements would feed it naturally if live. Deliberately omitted:
the database is static and synthetic. Conscious trade-off, not an oversight.

### No Upsert Logic

The generator inserts only. Appropriate for a controlled seed script against
a known-empty database. A production pipeline would require idempotent
load logic.

---

## Regeneration Instructions

Truncate tables in dependency order before regenerating:

```sql
TRUNCATE TABLE RepairJobs;
TRUNCATE TABLE RepairJobs_Staging;
TRUNCATE TABLE Calendar;
DELETE FROM Properties;  -- FK constraint from RepairJobs may prevent TRUNCATE
```

Then run:

```
py generate_data.py
```

Verify row counts in diagnostic output before proceeding to stored procedure
testing or Power BI refresh.

---

## Related Documents

- `DISCLAIMER.md` -- synthetic data declaration
- `Docs/schema.md` -- full database schema
- `spec_GetContractorPerformance.md` -- contractor KPI procedure
- `spec_ReportingCalendar.md` -- Power BI reporting calendar M-code
