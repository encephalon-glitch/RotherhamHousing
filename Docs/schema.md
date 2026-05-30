# Database Schema Reference

## Important Disclaimer

All data in this project is entirely synthetic and randomly generated.
This schema does not represent any real operational system.
See `DISCLAIMER.md` at the project root for full details.

---

## Overview

The database `RotherhamHousingRepairs` is structured as a lightweight
star schema -- a central fact table supported by dimension and reference
tables, with a staging layer for data validation prior to fact load.

---

## Tables

### `dbo.Contractors`

Contractor reference data.

| Column | Type | Notes |
|---|---|---|
| ContractorID | INT | Primary key |
| ContractorName | VARCHAR(100) | Mears, Equans, Direct Works |

---

### `dbo.RepairCategories`

Job category and group reference. Supports Awaab's Law damp and mould
compliance tracking via `CategoryGroup`.

| Column | Type | Notes |
|---|---|---|
| CategoryID | INT | Primary key |
| CategoryName | VARCHAR(100) | e.g. Damp and Mould, Electrical |
| CategoryGroup | VARCHAR(100) | e.g. Damp/Mould, Structural |

---

### `dbo.Properties`

Synthetic housing stock -- 500 properties across Rotherham wards.

| Column | Type | Notes |
|---|---|---|
| PropertyRef | VARCHAR(10) | Primary key -- e.g. PROP0001 |
| Ward | VARCHAR(100) | Rotherham ward name |
| PropertyType | VARCHAR(50) | House, Flat, Bungalow |
| Bedrooms | INT | 1 to 4 |
| EPCRating | CHAR(1) | A to E |
| BuildYear | INT | 1920 to 2020 |
| IsDecent | BIT | 0 = non-decent, 1 = decent homes standard met |

---

### `dbo.Calendar`

Date dimension covering the synthetic data period.

| Column | Type | Notes |
|---|---|---|
| DateKey | DATE | Primary key |
| MonthNumber | INT | 1 to 12 |
| MonthName | VARCHAR(20) | e.g. April |
| Quarter | INT | 1 to 4 |
| FiscalYear | VARCHAR(10) | e.g. 2025/26 |
| IsWorkingDay | BIT | 0 = weekend, 1 = working day |

---

### `dbo.RepairJobs_Staging`

Raw staging layer. Jobs are inserted here first and validated before
loading into the clean fact table.

| Column | Type | Notes |
|---|---|---|
| JobID | INT | Primary key, identity |
| PropertyRef | VARCHAR(10) | FK to Properties |
| CategoryID | INT | FK to RepairCategories |
| Priority | VARCHAR(20) | Emergency, Non-Emergency |
| DateRaised | DATE | Job raised date |
| DateCompleted | DATE | Nullable -- null if not completed |
| ContractorID | INT | FK to Contractors |
| Status | VARCHAR(20) | Completed, In Progress, Cancelled |
| RightFirstTime | BIT | Nullable -- null if not completed |
| TenantSatisfactionScore | INT | Nullable -- 1 to 5 |

---

### `dbo.RepairJobs`

Clean fact table. Loaded from staging after validation. 1,000 synthetic
repair jobs covering the 2025/26 financial year.

Same structure as `RepairJobs_Staging`. Only rows passing validation
rules are promoted:

- `PropertyRef` is not null
- `CategoryID` is not null
- `Priority` is Emergency or Non-Emergency
- `Status` is Completed, In Progress or Cancelled

---

## Views

### `vw_RepairJobs_Detail`

Fully joined view across `RepairJobs`, `Contractors`, `RepairCategories`,
`Properties` and `Calendar`. Primary source for ad-hoc analysis and
Plotly visualisation layer.

### `vw_KPI_Summary`

Aggregated KPI summary across all contractors. Provides a quick snapshot
without executing the full stored procedure.

---

## Stored Procedures

### `dbo.GetContractorPerformance`

Full specification in `spec_GetContractorPerformance.md`

Contractor KPI reporting across configurable reporting windows. Supports
four reporting modes -- last fiscal year, last quarter, last two quarters,
and fiscal year to date. KPI targets are fully parameterised to support
policy changes without code modifications.