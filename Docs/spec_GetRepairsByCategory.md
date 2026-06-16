# Procedure Spec: dbo.GetRepairsByCategory

## Important Disclaimer

This specification relates to a portfolio project built entirely on
synthetic data. It is not affiliated with or representative of Rotherham
Metropolitan Borough Council or any real operational system. See
`DISCLAIMER.md` at the project root for full details.

---

## Purpose

Returns category-level repair volume and Awaab's Law compliance metrics
across all three priority bands -- Emergency, Urgent, and Non-Emergency.
Designed to support Awaab's Law compliance monitoring, damp and mould
workload analysis, repeat repair identification, and RSH audit readiness.

Contractor-level performance reporting (completion rates by contractor,
Right First Time, tenant satisfaction) is covered by
`dbo.GetContractorPerformance`.

---

## Versioning

| Version | Status | Notes |
|---|---|---|
| v1.0 | Complete | Initial build. |
| v1.1 | Complete | Three-band RAG (Emergency/Urgent/Non-Emergency), #CategoryMetrics and #RepeatDampProperties staging tables, priority-aware NULL discipline. Committed. |
| v1.2 | Complete | Non-Emergency SLA evaluation flipped from calendar days to working days via dbo.fn_WorkingDaysBetween, consistent with GetContractorPerformance v1.5. Emergency and Urgent remain as calendar days -- legislative definitions. |
| v1.3 | Complete | CancelledJobs added to staging SELECT and final output alongside existing NoAccessCount. Both are volume signals only -- no RAG applied. Surfaces job lifecycle transparency for audit and RSH review without distorting compliance KPIs. NULL RAG branch moved to first position in all three RAG CASE blocks for consistency with GetContractorPerformance v1.6. |

---

## Audience

- BI team -- procedure is the data source for dashboard and visualisation
  layers
- Housing Repairs managers -- Awaab's Law compliance monitoring and
  damp/mould workload tracking
- RSH inspection readiness -- audit-ready, self-documenting output with
  all thresholds echoed in every result set
- Legal and compliance -- evidence of three-band SLA adherence and
  repeat repair identification

---

## Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@CategoryID` | INT | NULL | NULL returns all categories |
| `@DateFrom` | DATE | NULL | Defaults to 2024-04-01 if not supplied |
| `@DateTo` | DATE | NULL | Defaults to 2025-03-31 if not supplied |
| `@TargetEmergencyDays` | INT | 1 | Calendar days -- Awaab's Law legislative definition |
| `@TargetUrgentDays` | INT | 14 | Calendar days -- Awaab's Law legislative definition |
| `@TargetNonEmergencyDays` | INT | 20 | Working days -- housing repairs convention |
| `@TargetComplianceGreen` | DECIMAL(5,1) | 95.0 | Applied across all three priority bands -- design decision |
| `@TargetComplianceAmber` | DECIMAL(5,1) | 90.0 | Convention: 5 points below Green -- design decision, not a published standard |
| `@RepeatDampThreshold` | INT | 2 | Properties with this many or more damp/mould jobs flagged as repeat |

---

## KPIs Covered

| KPI | Target | Day Type | RAG Logic |
|---|---|---|---|
| Emergency compliance % | Within 1 day | Calendar days -- legislative definition | Green / Amber / Red / NULL |
| Urgent compliance % | Within 14 days | Calendar days -- legislative definition | Green / Amber / Red / NULL |
| Non-Emergency compliance % | Within 20 days | Working days -- housing repairs convention | Green / Amber / Red / NULL |
| Cancelled jobs | Volume count | Not applicable | No RAG -- lifecycle signal only |
| No Access count | Volume count | Not applicable | No RAG -- lifecycle signal only |
| Repeat damp properties | Property count | Not applicable | No RAG -- Awaab's Law monitoring signal |

---

## Business Measures

Each measure below documents the exact logic applied in the procedure.
A reader should be able to reproduce any figure from this section alone.

---

### TotalJobs

Count of all repair jobs raised in the reporting period for the category,
regardless of priority or status.

```
COUNT(JobID)
WHERE DateRaised BETWEEN @DateFrom AND @DateTo
```

Includes Cancelled and No Access jobs. TotalJobs represents full demand
volume -- excluding non-completed jobs would understate workload and
misrepresent resource consumption.

---

### EmergencyJobs / UrgentJobs / NonEmergencyJobs

Volume counts partitioned by priority band. Used as denominators in
compliance KPIs and as contextual workload volume.

```
EmergencyJobs    = SUM(IIF(Priority = 'Emergency',     1, 0))
UrgentJobs       = SUM(IIF(Priority = 'Urgent',        1, 0))
NonEmergencyJobs = SUM(IIF(Priority = 'Non-Emergency', 1, 0))
```

---

### EmergencyCompliancePct

Percentage of Emergency jobs completed within 1 calendar day.
Calendar days are used because the Emergency threshold is a legal
definition under Awaab's Law and applies regardless of weekends
or bank holidays.

```
Numerator:   Emergency jobs where Status = 'Completed'
             AND DaysToComplete <= @TargetEmergencyDays
Denominator: All Emergency jobs (including incomplete, cancelled, no access)
Formula:     ROUND(100.0 * numerator / NULLIF(denominator, 0), 1)
```

`DaysToComplete` is a computed column: `DateCompleted - DateRaised`
in calendar days. NULL where DateCompleted is NULL, which correctly
excludes incomplete jobs from the numerator without an additional guard.

RAG thresholds (default): Green >= 95.0%, Amber >= 90.0%, Red < 90.0%

---

### UrgentCompliancePct

Percentage of Urgent jobs completed within 14 calendar days.
Calendar days are used because the Urgent threshold is a legal
definition under Awaab's Law and applies regardless of weekends
or bank holidays.

```
Numerator:   Urgent jobs where Status = 'Completed'
             AND DaysToComplete <= @TargetUrgentDays
Denominator: All Urgent jobs (including incomplete, cancelled, no access)
Formula:     ROUND(100.0 * numerator / NULLIF(denominator, 0), 1)
```

RAG thresholds (default): Green >= 95.0%, Amber >= 90.0%, Red < 90.0%

---

### NonEmergencyCompliancePct

Percentage of Non-Emergency jobs completed within 20 working days.
Working days are used because housing repairs convention measures
Non-Emergency SLA in working days, not calendar days.

`dbo.fn_WorkingDaysBetween` is called directly on `DateRaised` and
`DateCompleted` rather than using the `DaysToComplete` computed column,
which is calendar days. Using `DaysToComplete` against a working-day
target would silently overstate compliance.

```
Numerator:   Non-Emergency jobs where Status = 'Completed'
             AND fn_WorkingDaysBetween(DateRaised, DateCompleted) <= @TargetNonEmergencyDays
Denominator: All Non-Emergency jobs (including incomplete, cancelled, no access)
Formula:     ROUND(100.0 * numerator / NULLIF(denominator, 0), 1)
```

`fn_WorkingDaysBetween` returns NULL when either date is NULL.
Incomplete jobs therefore return NULL from the function and fall
out of the numerator without a separate status filter.

RAG thresholds (default): Green >= 95.0%, Amber >= 90.0%, Red < 90.0%

---

### CancelledJobs

Count of jobs with Status = 'Cancelled' within the reporting period
for the category. Volume signal only -- no RAG applied.

```
SUM(IIF(Status = 'Cancelled', 1, 0))
```

Cancelled jobs remain in TotalJobs and in their priority band count.
Removing them would understate demand. Surfacing the count separately
gives auditors and RSH inspectors visibility of jobs that did not
progress to completion without distorting compliance percentages.

Note: cancellation reason and authorisation detail sit in the
RepairJobs fact table, not in this procedure.

---

### NoAccessCount

Count of jobs with Status = 'No Access' within the reporting period
for the category. Volume signal only -- no RAG applied.

```
SUM(IIF(Status = 'No Access', 1, 0))
```

No Access jobs remain in TotalJobs and in their priority band count.
A job attempted but refused access is a meaningful compliance signal
under Awaab's Law, which requires landlords to make every effort to
gain access and maintain documented records of all attempts.

Note: access attempt history and the three-stage documented process
sit in the RepairJobs fact table, not in this procedure.

---

### RepeatDampProperties

Count of distinct properties with two or more damp/mould jobs raised
in the reporting period, based on the parameterised
`@RepeatDampThreshold`. Calculated in a separate staging table
`#RepeatDampProperties` to avoid complicating the main aggregation.

```
Properties where CategoryGroup = 'Damp/Mould'
AND COUNT(JobID) >= @RepeatDampThreshold
grouped by PropertyRef
```

Surfaced in the output only for rows where CategoryGroup = 'Damp/Mould'.
All other categories return NULL. No RAG applied -- monitoring signal
for Awaab's Law proactive compliance and investment planning.

---

### RAG Evaluation

RAG status is evaluated in a second SELECT against the staged temp
table `#CategoryMetrics`, after all percentage calculations are
complete. This separates calculation from classification and avoids
repeating aggregation logic inside CASE expressions.

A single pair of Green/Amber thresholds (`@TargetComplianceGreen` and
`@TargetComplianceAmber`) applies across all three priority bands.
This is a deliberate design decision -- the compliance question is the
same regardless of priority band, only the SLA day threshold differs.

```
EmergencyRAG:    NULL  if EmergencyCompliancePct    IS NULL
                 Green if EmergencyCompliancePct    >= @TargetComplianceGreen
                 Amber if EmergencyCompliancePct    >= @TargetComplianceAmber
                 Red   otherwise

UrgentRAG:       NULL  if UrgentCompliancePct       IS NULL
                 Green if UrgentCompliancePct       >= @TargetComplianceGreen
                 Amber if UrgentCompliancePct       >= @TargetComplianceAmber
                 Red   otherwise

NonEmergencyRAG: NULL  if NonEmergencyCompliancePct IS NULL
                 Green if NonEmergencyCompliancePct >= @TargetComplianceGreen
                 Amber if NonEmergencyCompliancePct >= @TargetComplianceAmber
                 Red   otherwise
```

NULL RAG means no jobs of that priority band exist in the category for
the reporting period -- not a compliance failure. NULL branch evaluated
first, consistent with NULL discipline throughout and with
`dbo.GetContractorPerformance` v1.6.

All thresholds are passed as parameters and echoed in the output
so that exported result sets are self-documenting.

---

## Output Columns

- CategoryID, CategoryName, CategoryGroup
- Reporting period (PeriodFrom, PeriodTo)
- Volume metrics -- TotalJobs, EmergencyJobs, UrgentJobs, NonEmergencyJobs
- KPI percentages -- EmergencyCompliancePct, UrgentCompliancePct,
  NonEmergencyCompliancePct
- Lifecycle signals -- CancelledJobs, NoAccessCount
- RepeatDampProperties (Damp/Mould rows only, NULL elsewhere)
- RAG status -- EmergencyRAG, UrgentRAG, NonEmergencyRAG
- Threshold transparency columns -- TargetEmergencyDays, TargetUrgentDays,
  TargetNonEmergencyDays, TargetComplianceGreen, TargetComplianceAmber,
  RepeatDampThreshold

---

## Design Principles

- `@DateFrom` and `@DateTo` control the reporting window -- defaults to 2024/25
  fiscal year if not supplied; override for any ad-hoc period without code changes
- Emergency and Urgent SLA evaluated in calendar days -- legislative definitions
  under Awaab's Law, apply regardless of weekends or bank holidays
- Non-Emergency SLA evaluated in working days via `dbo.fn_WorkingDaysBetween` --
  consistent with GetContractorPerformance v1.6 and Power BI calendar logic
- Single compliance RAG threshold pair applied across all priority bands --
  the compliance question is the same; only the day target differs
- CancelledJobs and NoAccessCount are volume signals only -- they surface
  job lifecycle without distorting compliance KPIs or denominators
- RepeatDampProperties calculated in a separate staging table to keep
  the main aggregation clean
- NULL RAG returned where no jobs of a priority band exist in a category --
  not defaulted to Red; NULL branch evaluated first in all RAG CASE blocks
- `NULLIF` guards against division by zero throughout
- Temp table staging separates calculation from RAG evaluation
- Output is self-documenting -- all thresholds echoed in every result set
- Error handling returns meaningful messages upstream to BI tools and
  calling applications
- Built to support RSH inspection readiness -- audit trail baked in
  by design

---

## Example Calls

```sql
-- Default: last full fiscal year, all categories
EXEC dbo.GetRepairsByCategory;

-- Damp/Mould category only
EXEC dbo.GetRepairsByCategory
    @CategoryID = 1;

-- Custom date range
EXEC dbo.GetRepairsByCategory
    @DateFrom = '2025-10-01',
    @DateTo   = '2025-12-31';

-- Tightened compliance targets
EXEC dbo.GetRepairsByCategory
    @TargetComplianceGreen = 98.0
  , @TargetComplianceAmber = 95.0;

-- Lower repeat damp threshold for closer monitoring
EXEC dbo.GetRepairsByCategory
    @RepeatDampThreshold = 1;
```

---
