# # Procedure Spec: dbo.GetRepairsByCategory

## Important Disclaimer

This specification relates to a portfolio project built entirely on
synthetic data. It is not affiliated with or representative of Rotherham
Metropolitan Borough Council or any real operational system. See
`DISCLAIMER.md` at the project root for full details.

---

## Purpuse | Awaab's Law Context

Awaab Ishak was a two-year-old who died in December 2020 from prolonged mould exposure in social housing in Rochdale. The coroner's inquest (2022) found the landlord had failed to act on repeated reports. Awaab's Law came into force January 2024 under the Social Housing (Regulation) Act 2023.

It imposes legally binding response time obligations on social landlords -- not KPI targets. Legal obligations with enforcement teeth.

This procedure is designed to **evidence compliance**, not just report performance.

---

## Reporting Window Default

Aligned to synthetic data: **2025/26 financial year**

- `@DateFrom` default: `2025-04-01`
- `@DateTo` default: `2026-03-31`

---

## Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@CategoryGroup` | `VARCHAR(50)` | `NULL` | Filter to specific group. NULL returns all. |
| `@ContractorName` | `VARCHAR(100)` | `NULL` | Filter to one contractor. NULL returns all. |
| `@DateFrom` | `DATE` | `2025-04-01` | Start of reporting period. |
| `@DateTo` | `DATE` | `2026-03-31` | End of reporting period. |
| `@AwaabsEmergencyDays` | `INT` | `1` | Awaab's Law emergency response threshold (days). |
| `@AwaabsUrgentDays` | `INT` | `14` | Awaab's Law urgent response threshold (days). |
| `@AwaabsRoutineDays` | `INT` | `90` | Awaab's Law routine response threshold (days). |
| `@WinterMonthStart` | `INT` | `11` | Winter period start month (November). |
| `@WinterMonthEnd` | `INT` | `3` | Winter period end month (March). |

---

## Staging Architecture

Two temp tables, not one.

**Why two:**
Repeat damp property logic operates at **property grain** (`PropertyRef` level). All other metrics operate at **CategoryName + ContractorName grain**. Forcing both into one staging table would require subqueries or window functions mid-aggregation -- harder to maintain, harder to audit.

---

### `#CategoryMetrics` | job-level aggregation

Grain: `CategoryName + ContractorName`

Calculates:
- Job volumes
- Average and maximum days to complete
- Awaab's compliance per priority band (pre-calculated for clean RAG evaluation)
- No Access counts and rates
- Seasonal (winter/summer) split

---

### `#RepeatDampProperties` | property-level aggregation

Grain: `PropertyRef` (Damp/Mould jobs only)

Calculates:
- Distinct properties with more than one damp/mould job in the reporting period
- Aggregated to `CategoryName + ContractorName` before joining into final SELECT

---

## Output Columns

### Grouping
| Column | Notes |
|---|---|
| `CategoryGroup` | |
| `CategoryName` | |
| `ContractorName` | |
| `PeriodFrom` | |
| `PeriodTo` | |

### Volume
| Column | Notes |
|---|---|
| `TotalJobs` | |
| `IsDampMould` | BIT (1/0). Cleaner than a string match for BI filtering. |

### Response Time
| Column | Notes |
|---|---|
| `AvgDaysToComplete` | Completed jobs only. Unresolved jobs are not completion data. |
| `MaxDaysToComplete` | Completed jobs only. |
| `JobsCompletedWithinTarget` | Priority-aware threshold applied per job. |
| `CompliancePct` | Completed jobs within target / all completed jobs. |

### Awaab's Law (Damp/Mould rows only -- NULL elsewhere)
| Column | Notes |
|---|---|
| `AwaabsRAG` | Green / Amber / Red string. Human readable. |
| `ComplianceFlag` | BIT: 1 = compliant, 0 = non-compliant, NULL = not applicable or no completed damp jobs. |

**RAG bands (internal reporting, NOT statutory definitions!):**
- Green = 100% compliant
- Amber = >= 90% compliant
- Red = < 90% compliant

### No Access
| Column | Notes |
|---|---|
| `NoAccessJobs` | Status = 'No Access' confirmed in data. |
| `NoAccessPct` | NoAccessJobs / TotalJobs. |

### Repeat Damp Properties (Damp/Mould rows only, NULL elsewhere)
| Column | Notes |
|---|---|
| `PropertiesWithRepeatDampJobs` | Distinct properties with more than one damp job in period. |
| `TotalDampProperties` | Distinct properties with any damp job in period. |
| `RepeatDampPct` | PropertiesWithRepeatDampJobs / TotalDampProperties. |

### Seasonal
| Column | Notes |
|---|---|
| `WinterJobs` | Jobs raised in winter window. |
| `SummerJobs` | Jobs raised outside winter window. |
| `WinterPct` | WinterJobs / TotalJobs. |

### Transparency
| Column | Notes |
|---|---|
| `AwaabsEmergencyDays` | Parameter value used in this run. |
| `AwaabsUrgentDays` | Parameter value used in this run. |
| `AwaabsRoutineDays` | Parameter value used in this run. |
| `WinterMonthStart` | Parameter value used in this run. |
| `WinterMonthEnd` | Parameter value used in this run. |
| `ReportTimestamp` | `GETDATE()` at execution. |

---

## Key Logic Decisions

### Priority-aware Awaab's RAG

Threshold applied depends on job `Priority`:

| Priority | Threshold Parameter | Default |
|---|---|---|
| Emergency | `@AwaabsEmergencyDays` | 1 day |
| Urgent | `@AwaabsUrgentDays` | 14 days |
| Non-Emergency | `@AwaabsRoutineDays` | 90 days |

Only `Completed` jobs are measured. In Progress, Cancelled, and No Access are excluded from the compliance numerator.

---

### NULL Discipline

| Value | Meaning |
|---|---|
| `NULL` | Not applicable -- scope decision (Awaab's, repeat damp on non-damp rows) |
| `0` | Measured -- result was zero (performance result) |

These are not interchangeable in audit output or BI aggregations.

---

### Repeat Damp Threshold

More than one damp/mould job at the same property within the reporting period. No tighter sub-window applied. Conservative threshold -- catches more cases. Right bias for a compliance context.

---

### No Access Definition

`Status = 'No Access'` in `RepairJobs`. Confirmed present in data (added v1.1 of data generation).

---

### Seasonal Definition

Winter = months between `@WinterMonthStart` and `@WinterMonthEnd`.

Cross-year window (e.g. November=11 through March=3): handled with OR condition (`>= Start OR <= End`) rather than BETWEEN, which would fail across a year boundary.

---

### Error Handling

Same `TRY/CATCH` Returns meaningful SQL errors upstream.

---

## Example Calls

```sql
-- All categories, all contractors, 2025/26 fiscal year
EXEC dbo.GetRepairsByCategory;


-- Damp/Mould only, Direct Works, full year
EXEC dbo.GetRepairsByCategory
      @CategoryGroup   = 'Damp/Mould'
    , @ContractorName  = 'Direct Works';

-- Override Awaab's thresholds
EXEC dbo.GetRepairsByCategory
      @CategoryGroup        = 'Damp/Mould'
    , @AwaabsEmergencyDays  = 1
    , @AwaabsUrgentDays     = 7
    , @AwaabsRoutineDays    = 60;
```

---

## Design Principles

- Professional inline comments: WHY not WHAT
- Parameterised targets and date defaults
- Dynamic fiscal year default aligned to synthetic data
- Self-documenting output with `ReportTimestamp`
- "Built to outlast us": no hardcoded assumptions

---

## Versioning

| Version | Status | Notes |
|---|---|---|
| v1.0 | Complete | commited working, tested base code |
