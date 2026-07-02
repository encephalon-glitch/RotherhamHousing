# Database Schema Reference

## Important Disclaimer

All data in this project is entirely synthetic and randomly generated.
This schema does not represent any real operational system.
See `DISCLAIMER.md` at the project root for full details.

---

## Version History

| Version | Changes |
|---------|---------|
| v1.1 | Full rewrite against current build state. WardGeometry table added (missing entirely from v1.0). Properties, Calendar, RepairJobs and RepairJobs_Staging columns corrected to match actual DDL -- several column names and enumerated values had drifted from v1.0's description. Functions section added (fn_WorkingDaysBetween). Views section expanded from two named objects to all four built views, each with a one-line purpose and a pointer to its spec where one exists. GetRepairsByCategory added to Stored Procedures. GetContractorPerformance description corrected -- reporting modes were descoped in spec v1.4 and no longer exist. |
| v1.0 | Initial schema reference. Tables and two named views only. Predates WardGeometry, fn_WorkingDaysBetween, vw_PropertyStats, vw_RepeatRepairs, and GetRepairsByCategory. |

---

## Overview

The database `RotherhamHousingRepairs` is structured as a lightweight
star schema -- a central fact table supported by dimension and reference
tables, with a staging layer for data validation prior to fact load.

Current object count: 6 tables, 1 scalar function, 4 views, 2 stored
procedures. This document is a structural index -- column names, types
and relationships. Business logic, KPI formulas, RAG thresholds and
design rationale live in the dedicated `spec_*.md` documents and are
not repeated here. Where no dedicated spec exists yet, that gap is
noted rather than backfilled into this document.

---

## Tables

### `dbo.WardGeometry`

Geographic dimension. 25 Rotherham MBC wards, ONS boundary review 2024.
Source: ONS Open Geography Portal (Open Government Licence).

| Column | Type | Notes |
|---|---|---|
| WardID | INT IDENTITY | Primary key |
| WD24CD | VARCHAR(20) | ONS ward code, unique. Join key for GeoJSON map layer -- avoids fragile ward-name string matching |
| WD24NM | VARCHAR(100) | Ward name |
| WDLat | DECIMAL(9,6) | Centroid latitude, nullable |
| WDLon | DECIMAL(9,6) | Centroid longitude, nullable |

---

### `dbo.Contractors`

| Column | Type | Notes |
|---|---|---|
| ContractorID | INT IDENTITY | Primary key |
| ContractorName | VARCHAR(100) | Mears, Equans, Direct Works |
| ContractType | VARCHAR(20) | Both, Planned, Emergency -- reflects real contract structure (Equans: no Emergency jobs; Direct Works: no Non-Emergency jobs) |

---

### `dbo.RepairCategories`

12 categories across 6 groups. Supports Awaab's Law damp/mould tracking
via `CategoryGroup`.

| Column | Type | Notes |
|---|---|---|
| CategoryID | INT IDENTITY | Primary key |
| CategoryName | VARCHAR(100) | e.g. Damp and Mould, Boiler Repair |
| CategoryGroup | VARCHAR(50) | Damp/Mould, Heating, Electrical, Structural, Plumbing, General |

---

### `dbo.Properties`

500 synthetic properties.

| Column | Type | Notes |
|---|---|---|
| PropertyRef | VARCHAR(10) | Primary key -- e.g. PROP0001 |
| WardID | INT | FK to WardGeometry. Integer key, not ward name string |
| PropertyType | VARCHAR(20) | House, Flat, Bungalow |
| BedroomCount | INT | 1 to 4, property-type-aware distribution |
| EPC_Rating | CHAR(1) | A to E, property-type-aware distribution |
| BuildYear | INT | 1920 to 2020 |
| IsDecent | BIT | Default 1. 0 = non-decent, 1 = decent homes standard met |

---

### `dbo.Calendar`

Date dimension, two financial years (2024/25, 2025/26).

| Column | Type | Notes |
|---|---|---|
| CalendarDate | DATE | Primary key |
| MonthNum | INT | 1 to 12 |
| MonthName | VARCHAR(20) | e.g. April |
| Quarter | INT | 1 to 4 |
| FinancialYear | VARCHAR(10) | e.g. 2025/26 |
| IsWorkingDay | BIT | Default 1. 0 = weekend or GOV.UK bank holiday |

---

### `dbo.RepairJobs_Staging`

Raw staging layer. Validated before promotion to the clean fact table --
see `spec_DataGenerator.md` for the validation filter.

| Column | Type | Notes |
|---|---|---|
| JobID | INT IDENTITY | Primary key |
| PropertyRef | VARCHAR(10) | Not yet FK-constrained at staging level by design |
| CategoryID | INT | |
| Priority | VARCHAR(15) | Emergency, Urgent, Non-Emergency |
| DateRaised | DATE | |
| DateCompleted | DATE | Nullable -- NULL if not completed |
| ContractorID | INT | |
| Status | VARCHAR(20) | Completed, In Progress, Cancelled, No Access |
| RightFirstTime | BIT | Nullable -- NULL if not completed |
| TenantSatisfactionScore | INT | Nullable -- 1 to 5, only populated for Completed |

---

### `dbo.RepairJobs`

Clean fact table. 2,000 synthetic jobs, FY2024/25 and FY2025/26 combined.
Loaded from staging -- only rows passing validation are promoted.

| Column | Type | Notes |
|---|---|---|
| JobID | INT | Primary key |
| PropertyRef | VARCHAR(10) | FK to Properties |
| CategoryID | INT | FK to RepairCategories |
| Priority | VARCHAR(15) | Emergency, Urgent, Non-Emergency |
| DateRaised | DATE | |
| DateCompleted | DATE | Nullable |
| ContractorID | INT | FK to Contractors |
| Status | VARCHAR(20) | Completed, In Progress, Cancelled, No Access |
| RightFirstTime | BIT | Nullable |
| TenantSatisfactionScore | INT | Nullable |
| DaysToComplete | INT, computed | `DATEDIFF(DAY, DateRaised, DateCompleted)`. Calendar days. NULL where DateCompleted is NULL |

**Note on scope:** `DaysToComplete` measures raised-to-completed elapsed
time against a single threshold per priority band. It does not evidence
Awaab's Law's actual multi-stage clock (investigation, written summary,
safety works tracked separately). See `spec_GetRepairsByCategory.md`,
Known Limitations, for the full statement of that scope boundary.

---

## Relationships

```
WardGeometry (1) -----< (many) Properties
Properties   (1) -----< (many) RepairJobs
RepairCategories (1) --< (many) RepairJobs
Contractors  (1) -----< (many) RepairJobs
Calendar.CalendarDate -- joined to RepairJobs.DateRaised in views, not a declared FK
```

`RepairJobs_Staging` carries no foreign key constraints -- intentional.
Staging exists to catch malformed rows before they reach a constrained
table; an FK violation at staging would defeat the point of the layer.

---

## Functions

### `dbo.fn_WorkingDaysBetween`

Scalar function. Returns working days between two dates -- exclusive
start, inclusive end -- against the `Calendar.IsWorkingDay` flag.
NULL in, NULL out. Same-day or negative range returns 0.

Full spec: `spec_fn_WorkingDaysBetween.md`

Consumed by: `GetContractorPerformance`, `GetRepairsByCategory`,
`vw_RepairJobs_Detail` (Non-Emergency band only in all three -- Emergency
and Urgent are evaluated in calendar days as legislative/operational
conventions, not working days).

---

## Views

### `dbo.vw_RepairJobs_Detail` (v1.1)

Fully joined row-level detail across RepairJobs, Properties,
WardGeometry, RepairCategories, Contractors and Calendar. Adds
`WorkingDaysToComplete` (NULL for Emergency/Urgent by design),
`EmergencyOnTarget` / `UrgentOnTarget` / `NonEmergencyOnTarget` flags,
and `IsAwaabJob`. Primary source for ad-hoc analysis, the Plotly layer,
and the Power BI semantic model. No dedicated spec file -- versioning
and rationale currently live only in the in-file header comment block.

### `dbo.vw_KPI_Summary`

Aggregates KPIs by FinancialYear, Quarter, Month and Contractor against
Rotherham's published targets, as a lightweight snapshot that doesn't
require executing `GetContractorPerformance`. No dedicated spec, no
version header in the file.

**Flag for review:** `NonEmergencyCompletionPct` in this view evaluates
against `r.DaysToComplete <= 20` -- calendar days. Both
`GetContractorPerformance` (v1.5+) and `GetRepairsByCategory` (v1.2+)
were corrected to evaluate Non-Emergency against
`fn_WorkingDaysBetween` instead, specifically because the calendar-day
basis overstates compliance. This view does not appear to have received
that same fix. Worth confirming whether that's intentional (unlikely,
given no comment explains it) or a residual instance of the exact gap
already closed elsewhere.

### `dbo.vw_PropertyStats`

Pivots EPC rating counts and decent-homes status by ward and property
type. Source for `PropertyStockMap.py`'s choropleth layers and EPC
composite score. No dedicated spec, no version header in the file.

**Flag for review:** the in-file header comment contains non-ASCII
characters (mangled smart quotes around "pivoted") -- inconsistent with
the ASCII-safe scripting standard applied elsewhere in the codebase.
Cosmetic, but a five-second fix.

### `dbo.vw_RepeatRepairs` (v1.0)

Two-level LAG() view -- within-category and cross-category gap signals
per job, at property level. No threshold or flag logic; interpretation
belongs to the consuming layer.

Full spec: `spec_RepeatRepairs.md`

---

## Stored Procedures

### `dbo.GetContractorPerformance` (v1.6)

Contractor-level KPI reporting -- Emergency and Non-Emergency completion
against parameterised RAG thresholds, Right First Time, tenant
satisfaction, damp/mould volume. Reporting is controlled by `@DateFrom`
/ `@DateTo` with fiscal-year defaults; named reporting modes (last
quarter, FYTD, etc.) were evaluated and descoped in spec v1.4 in favour
of direct date parameters.

Full spec: `spec_GetContractorPerformance.md`

### `dbo.GetRepairsByCategory` (v1.3)

Category-level repair volume and three-band compliance (Emergency,
Urgent, Non-Emergency) plus lifecycle signals (CancelledJobs,
NoAccessCount) and repeat damp/mould property detection.

Full spec: `spec_GetRepairsByCategory.md`

---

## Related Documents

- `DISCLAIMER.md` -- synthetic data declaration
- `spec_DataGenerator.md` -- synthetic data generation logic
- `spec_fn_WorkingDaysBetween.md`
- `spec_GetContractorPerformance.md`
- `spec_GetRepairsByCategory.md`
- `spec_RepeatRepairs.md`
- `spec_ReportingCalendar.md` -- Power BI reporting calendar (M-code, not SQL)
