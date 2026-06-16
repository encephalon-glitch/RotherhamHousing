# Function Spec: dbo.fn_WorkingDaysBetween

## Important Disclaimer

This specification relates to a portfolio project built entirely on
synthetic data. It is not affiliated with or representative of Rotherham
Metropolitan Borough Council or any real operational system. See
`DISCLAIMER.md` at the project root for full details.

---

## Purpose

Scalar function returning the number of working days between two dates,
inclusive of the end date and exclusive of the start date. Queries the
`dbo.Calendar` dimension directly, which carries bank holiday flags
sourced from the GOV.UK bank holiday API. This makes the function
accurate for Awaab's Law Non-Emergency SLA evaluation, where a
20-working-day target must exclude weekends and bank holidays.

Used as a dependency by `dbo.GetContractorPerformance` and
`dbo.GetRepairsByCategory` for Non-Emergency completion evaluation.
Emergency (1 calendar day) and Urgent (14 calendar days) thresholds
are legislative definitions and are evaluated against `DaysToComplete`
directly -- this function is not called for those priority bands.

---

## Versioning

| Version | Status | Notes |
|---|---|---|
| v1.0 | Complete | Initial build and tested. All four test cases green: basic working day count, bank holiday exclusion, NULL guard, same-day returns zero. Live in database. |

---

## Audience

- BI team -- function is a dependency of both reporting SPs; behaviour
  must be understood before modifying either SP
- Any developer extending the reporting layer with working-day-based
  SLA evaluation

---

## Signature

```sql
dbo.fn_WorkingDaysBetween (
      @StartDate DATE
    , @EndDate   DATE
)
RETURNS INT
```

---

## Parameters

| Parameter | Type | Notes |
|---|---|---|
| `@StartDate` | DATE | Exclusive -- the start date itself is not counted as a working day elapsed. In a repairs context this is DateRaised: the day a job is raised does not count toward the SLA. |
| `@EndDate` | DATE | Inclusive -- the end date is counted if it is a working day. In a repairs context this is DateCompleted: the completion day counts toward the SLA. |

---

## Return Value

| Condition | Return Value |
|---|---|
| Either parameter is NULL | NULL |
| @StartDate >= @EndDate (same day or negative range) | 0 |
| Valid date range | Count of working days in dbo.Calendar where CalendarDate > @StartDate AND CalendarDate <= @EndDate AND IsWorkingDay = 1 |

---

## Business Logic

### Boundary convention -- exclusive start, inclusive end

The function counts working days strictly after `@StartDate` and up to
and including `@EndDate`. This reflects housing repairs SLA convention:
a job raised on a Monday does not consume a working day on that Monday;
the clock starts the following working day. The completion day itself
counts as the final working day elapsed.

```
Example: DateRaised = Monday 7 April, DateCompleted = Wednesday 9 April
Working days elapsed = Tuesday 8 April + Wednesday 9 April = 2
```

### Working day definition

A working day is any day in `dbo.Calendar` where `IsWorkingDay = 1`.
The Calendar dimension excludes weekends and bank holidays sourced from
the GOV.UK bank holiday API (England and Wales division). The function
inherits this definition automatically -- no day-of-week logic is
hardcoded in the function itself.

```sql
SELECT COUNT(*)
FROM dbo.Calendar
WHERE CalendarDate >  @StartDate
  AND CalendarDate <= @EndDate
  AND IsWorkingDay = 1
```

### NULL behaviour

NULL in, NULL out. If either date is NULL the function returns NULL
immediately without querying the Calendar table. This is consistent
with NULL discipline throughout both calling SPs -- a NULL return
from the function correctly excludes incomplete jobs (where
DateCompleted is NULL) from SLA compliance numerators without
requiring a separate status filter in the calling code.

### Same-day and negative ranges

If `@StartDate >= @EndDate` the function returns 0. A job raised and
completed on the same calendar day has zero working days elapsed by
the exclusive-start convention. A negative range (DateCompleted before
DateRaised) is not a valid data state but returns 0 rather than a
negative number or an error, keeping the calling SP output clean.

---

## Dependencies

| Object | Type | Notes |
|---|---|---|
| `dbo.Calendar` | Table | Must be populated for the full date range being evaluated. An unpopulated or partially populated Calendar will cause undercounting with no error raised. |

---

## Known Constraints

- The function will silently undercount if `dbo.Calendar` is not
  populated for the date range being queried. No error is raised --
  missing calendar rows simply are not counted. Ensure the Calendar
  dimension covers the full reporting period before calling.
- Bank holiday accuracy depends on the GOV.UK API fetch being current.
  If the Calendar was populated without a successful API fetch,
  bank holidays will not be excluded and working day counts will be
  overstated by the number of bank holidays in the period.
- The function is not suitable for Emergency or Urgent SLA evaluation.
  Those thresholds are defined in legislation in calendar days and must
  be evaluated against `DaysToComplete` directly.

---

## Test Cases

All four test cases were validated against the live database before
the function was consumed by either SP.

| Test | Input | Expected | Result |
|---|---|---|---|
| Basic working day count | StartDate = Monday, EndDate = Friday (same week, no bank holidays) | 4 | Green |
| Bank holiday exclusion | Date range spanning a known bank holiday | Count excludes the bank holiday | Green |
| NULL guard | Either parameter NULL | NULL returned | Green |
| Same-day range | StartDate = EndDate | 0 returned | Green |

---

## Example Calls

```sql
-- Working days between a job raised and completed
SELECT dbo.fn_WorkingDaysBetween('2025-04-07', '2025-04-09');
-- Returns: 2 (Tuesday 8 April + Wednesday 9 April)

-- NULL DateCompleted returns NULL -- incomplete job excluded from numerator
SELECT dbo.fn_WorkingDaysBetween('2025-04-07', NULL);
-- Returns: NULL

-- Same day returns zero
SELECT dbo.fn_WorkingDaysBetween('2025-04-07', '2025-04-07');
-- Returns: 0

-- Typical usage in SP context (Non-Emergency SLA evaluation)
SELECT
      r.JobID
    , dbo.fn_WorkingDaysBetween(r.DateRaised, r.DateCompleted) AS WorkingDaysToComplete
FROM dbo.RepairJobs r
WHERE r.Priority = 'Non-Emergency';
```

---
