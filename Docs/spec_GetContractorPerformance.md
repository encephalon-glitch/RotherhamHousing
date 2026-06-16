# Procedure Spec: dbo.GetContractorPerformance

## Important Disclaimer

This specification relates to a portfolio project built entirely on
synthetic data. It is not affiliated with or representative of Rotherham
Metropolitan Borough Council or any real operational system. See
`DISCLAIMER.md` at the project root for full details.

---

## Purpose

Returns contractor-level performance metrics across Emergency and
Non-Emergency repair priorities for the selected period. Covers
completion rate against SLA thresholds, Right First Time percentage,
tenant satisfaction, and damp/mould workload volume. Designed to support
quarterly contract review meetings, RSH audit readiness, and Finance
cost performance reporting.

Urgent priority jobs are included in TotalJobs but are out of scope
for SLA KPI evaluation in this procedure. Awaab's Law three-tier
compliance reporting (Emergency, Urgent, Non-Emergency) is covered
by `dbo.GetRepairsByCategory`.

---

## Versioning

| Version | Status | Notes |
|---|---|---|
| v1.0 | Complete | Prototype -- single SELECT, hardcoded RAG thresholds |
| v1.1 | Complete | Temp table staging, parameterised targets |
| v1.2 | Complete | CREATE OR ALTER, input validation, error handling |
| v1.3 | Complete | IIF consolidation, dynamic dates, timestamp |
| v1.4 | Complete | Reporting period updated, descoped reporting modes, in-line comments added |
| v1.5 | Complete | Non-Emergency SLA evaluation flipped from calendar days to working days via dbo.fn_WorkingDaysBetween. Emergency (1 day) and Urgent (14 days) remain as calendar days -- those thresholds are defined in legislation and apply regardless of weekends or bank holidays. DaysToComplete is a computed column (DateRaised to DateCompleted); the function is called directly against the source dates for Non-Emergency to avoid silent inconsistency between SP and Power BI calendar logic. |
| v1.6 | Complete | NULL RAG branches added for EmergencyRAG and NonEmergencyRAG. Contractors operating in a single priority band (Direct Works = Emergency only, Equans = Non-Emergency only) previously cascaded to Red on the inapplicable metric. NULL now returned instead -- consistent with NULL discipline throughout and with GetRepairsByCategory RAG logic. RightFirstTimeRAG unchanged as all contractors have RFT-scored jobs. Style normalised to consistent space indentation. |

---

## Audience

- BI team -- procedure is the data source for dashboard and visualisation
  layers
- Housing Repairs managers -- quarterly contract review meetings
- Finance -- annual budget projections and contractor cost performance
- RSH inspection readiness -- audit-ready, self-documenting output with
  all thresholds echoed in every result set

---

## Reporting Modes

> Reporting modes were evaluated and DESCOPED in v1.4. The existing
> `@DateFrom` and `@DateTo` parameters provide equivalent flexibility
> without additional complexity. May be revisited in future iterations
> if a BI tool integration requires named mode parameters.

---

## Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@ContractorName` | VARCHAR(100) | NULL | NULL returns all contractors |
| `@DateFrom` | DATE | NULL | Defaults to 2024-04-01 if not supplied |
| `@DateTo` | DATE | NULL | Defaults to 2025-03-31 if not supplied |
| `@TargetEmergencyGreen` | DECIMAL(5,1) | 98.0 | Sourced from Rotherham Q3 2025/26 published target |
| `@TargetEmergencyAmber` | DECIMAL(5,1) | 95.0 | Convention: 3 points below Green -- design decision, not a published standard |
| `@TargetNonEmergencyGreen` | DECIMAL(5,1) | 94.0 | Sourced from Rotherham Q3 2025/26 published target |
| `@TargetNonEmergencyAmber` | DECIMAL(5,1) | 90.0 | Convention: 4 points below Green -- design decision, not a published standard |
| `@TargetRFTGreen` | DECIMAL(5,1) | 93.0 | Sourced from Rotherham Q3 2025/26 published target |
| `@TargetRFTAmber` | DECIMAL(5,1) | 90.0 | Convention: 3 points below Green -- design decision, not a published standard |

---

## KPIs Covered

| KPI | Target | Day Type | RAG Logic |
|---|---|---|---|
| Emergency completion % | 98% within 1 day | Calendar days -- legislative definition | Green / Amber / Red / NULL |
| Non-emergency completion % | 94% within 20 days | Working days -- housing repairs convention | Green / Amber / Red / NULL |
| Right First Time % | 93% | Not applicable | Green / Amber / Red |
| Tenant satisfaction | Average score 1-5 | Not applicable | No RAG -- informational |
| Damp and mould jobs | Volume count | Not applicable | No RAG -- workload signal only |

---

## Business Measures

Each measure below documents the exact logic applied in the procedure.
A reader should be able to reproduce any figure from this section alone.

---

### TotalJobs

Count of all repair jobs raised in the reporting period for the
contractor, regardless of priority or status.

```
COUNT(JobID)
WHERE DateRaised BETWEEN @DateFrom AND @DateTo
```

Note: includes Urgent priority jobs, which are not evaluated in any
SLA KPI in this procedure. TotalJobs will not reconcile with
EmergencyJobs + NonEmergencyJobs where Urgent jobs exist.

---

### EmergencyJobs / NonEmergencyJobs

Volume counts partitioned by priority band. Used as denominators in
completion KPIs and as contextual volume for contract review.

```
EmergencyJobs    = SUM(IIF(Priority = 'Emergency',     1, 0))
NonEmergencyJobs = SUM(IIF(Priority = 'Non-Emergency', 1, 0))
```

---

### EmergencyCompletionPct

Percentage of Emergency jobs completed within 1 calendar day.
Calendar days are used because the Emergency threshold is a legal
definition under Awaab's Law and applies regardless of weekends
or bank holidays.

```
Numerator:   Emergency jobs where Status = 'Completed'
             AND DaysToComplete <= 1
Denominator: All Emergency jobs (including incomplete)
Formula:     ROUND(100.0 * numerator / NULLIF(denominator, 0), 1)
```

`DaysToComplete` is a computed column: `DateCompleted - DateRaised`
in calendar days. NULL where DateCompleted is NULL, which correctly
excludes incomplete jobs from the numerator without an additional guard.

RAG thresholds (default): Green >= 98.0%, Amber >= 95.0%, Red < 95.0%

Source: 98% Green threshold sourced from Rotherham Q3 2025/26
performance report. Amber threshold is a 3-point convention -- not
a published standard.

---

### NonEmergencyCompletionPct

Percentage of Non-Emergency jobs completed within 20 working days.
Working days are used because housing repairs convention measures
Non-Emergency SLA in working days, not calendar days.

`dbo.fn_WorkingDaysBetween` is called directly on `DateRaised` and
`DateCompleted` rather than using the `DaysToComplete` computed column,
which is calendar days. Using `DaysToComplete` against a working-day
target would silently overstate compliance.

```
Numerator:   Non-Emergency jobs where Status = 'Completed'
             AND fn_WorkingDaysBetween(DateRaised, DateCompleted) <= 20
Denominator: All Non-Emergency jobs (including incomplete)
Formula:     ROUND(100.0 * numerator / NULLIF(denominator, 0), 1)
```

`fn_WorkingDaysBetween` returns NULL when either date is NULL.
Incomplete jobs therefore return NULL from the function and fall
out of the numerator without a separate status filter.

RAG thresholds (default): Green >= 94.0%, Amber >= 90.0%, Red < 90.0%

Source: 94% Green threshold sourced from Rotherham Q3 2025/26
performance report. Amber threshold is a 4-point convention -- not
a published standard.

---

### RightFirstTimePct

Percentage of completed jobs resolved without a return visit. Excludes
jobs where `RightFirstTime` is NULL (i.e. non-completed jobs where the
flag was never recorded).

```
Numerator:   Jobs where RightFirstTime = 1
Denominator: Jobs where RightFirstTime IS NOT NULL
Formula:     ROUND(100.0 * numerator / NULLIF(denominator, 0), 1)
```

RAG thresholds (default): Green >= 93.0%, Amber >= 90.0%, Red < 90.0%

Source: 93% Green threshold sourced from Rotherham Q3 2025/26
performance report. Amber threshold is a 3-point convention -- not
a published standard.

---

### AvgSatisfaction

Mean tenant satisfaction score across all scored jobs for the
contractor. Scores are recorded as integers 1-5. Cast to FLOAT
before averaging to avoid integer truncation.

```
ROUND(AVG(CAST(TenantSatisfactionScore AS FLOAT)), 2)
```

No RAG applied -- informational only.

---

### DampMouldJobs

Volume count of jobs in the Damp/Mould category group across all
priorities. Provides a workload signal for Awaab's Law monitoring
at contractor level. No SLA evaluation is applied here -- see
`dbo.GetRepairsByCategory` for compliance detail.

```
SUM(IIF(CategoryGroup = 'Damp/Mould', 1, 0))
```

---

### RAG Evaluation

RAG status is evaluated in a second SELECT against the staged temp
table `#ContractorMetrics`, after all percentage calculations are
complete. This separates calculation from classification and avoids
repeating aggregation logic inside CASE expressions.

```
EmergencyRAG:    NULL  if EmergencyCompletionPct    IS NULL
                 Green if EmergencyCompletionPct    >= @TargetEmergencyGreen
                 Amber if EmergencyCompletionPct    >= @TargetEmergencyAmber
                 Red   otherwise

NonEmergencyRAG: NULL  if NonEmergencyCompletionPct IS NULL
                 Green if NonEmergencyCompletionPct >= @TargetNonEmergencyGreen
                 Amber if NonEmergencyCompletionPct >= @TargetNonEmergencyAmber
                 Red   otherwise

RightFirstTimeRAG: Green if RightFirstTimePct       >= @TargetRFTGreen
                   Amber if RightFirstTimePct        >= @TargetRFTAmber
                   Red   otherwise
```

NULL RAG means the metric does not apply to that contractor -- not a
data error. Contractors operating in a single priority band by contract
design (Direct Works = Emergency only, Equans = Non-Emergency only)
will return NULL on the inapplicable RAG column. This is consistent
with NULL discipline throughout the procedure and with
`dbo.GetRepairsByCategory` RAG logic.

RightFirstTimeRAG has no NULL branch because all contractors have
completed jobs with an RFT flag recorded. If that changes, a NULL
branch should be added for consistency.

All thresholds are passed as parameters and echoed in the output
so that exported result sets are self-documenting.

---

## Output Columns

- Contractor name, reporting period (PeriodFrom, PeriodTo)
- Volume metrics -- TotalJobs, EmergencyJobs, NonEmergencyJobs
- KPI percentages -- EmergencyCompletionPct, NonEmergencyCompletionPct,
  RightFirstTimePct, AvgSatisfaction
- DampMouldJobs count
- RAG status -- EmergencyRAG, NonEmergencyRAG, RightFirstTimeRAG
- Threshold transparency columns -- TargetEmergencyGreen/Amber,
  TargetNonEmergencyGreen/Amber, TargetRFTGreen/Amber

---

## Design Principles

- `@DateFrom` and `@DateTo` control the reporting window -- defaults to 2024/25
  fiscal year if not supplied; override for any ad-hoc period without code changes
- Non-Emergency SLA evaluated in working days via `dbo.fn_WorkingDaysBetween` --
  Emergency and Urgent remain calendar days, consistent with legislative definitions
- KPI targets are parameterised -- policy changes require no code changes
- Temp table staging separates calculation from RAG evaluation
- Output is self-documenting -- all KPI thresholds echoed in every result set
- NULL RAG returned where a metric does not apply -- not defaulted to Red
- `NULLIF` guards against division by zero where a contractor has no
  jobs in a category
- Error handling returns meaningful messages upstream to BI tools and
  calling applications
- Built to support RSH inspection readiness -- audit trail baked in
  by design

---

## Example Calls

```sql
-- Default: last full fiscal year, all contractors
EXEC dbo.GetContractorPerformance;

-- Mears only, last fiscal year
EXEC dbo.GetContractorPerformance
    @ContractorName = 'Mears';

-- Custom date range override
EXEC dbo.GetContractorPerformance
    @DateFrom = '2025-10-01',
    @DateTo   = '2025-12-31';

-- Tightened KPI targets
EXEC dbo.GetContractorPerformance
    @TargetEmergencyGreen    = 99.0
  , @TargetNonEmergencyGreen = 96.0
  , @TargetRFTGreen          = 95.0;
```

---
