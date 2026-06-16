# View Spec: dbo.vw_RepeatRepairs

## Important Disclaimer

This specification relates to a portfolio project built entirely on
synthetic data. It is not affiliated with or representative of Rotherham
Metropolitan Borough Council or any real operational system. See
`DISCLAIMER.md` at the project root for full details.

---

## Purpose

Surface consecutive repair job sequences at property level to support
Awaab's Law compliance monitoring and root cause analysis. The view
exposes two gap signals per job row:

- **Within-category gap** -- days since the previous job at the same
  property in the same category. Primary repeat repair signal.
- **Cross-category gap** -- days since the previous job at the same
  property regardless of category. Enables pattern detection across
  related repair types (e.g. a Structural job followed by Damp/Mould).

The view applies no threshold logic and raises no flags. Gap
interpretation belongs in the consuming layer -- a stored procedure,
DAX measure, or Power BI filter -- where the analyst or case worker
can apply context. Hardcoding a threshold here would produce misleading
signals without cross-category awareness.

---

## Versioning

| Version | Status  | Notes                          |
|---------|---------|--------------------------------|
| v1.0    | Current | Initial build. LAG() at two    |
|         |         | levels. No threshold logic.    |

---

## Audience

- BI team -- view is a data source for repeat repair dashboards and
  compliance drill-through
- Housing Repairs managers -- identifying properties with recurring
  issues for case escalation
- RSH inspection readiness -- audit-ready sequence data with full
  job context per row

---

## Parameters

This object is a view. It accepts no parameters.

Filtering by date range, category, priority, or gap threshold is the
responsibility of the consuming layer. Example patterns are provided
in the Example Calls section below.

---

## Business Measures

### JobSequence (within-category)

Identifies the ordinal position of each job within the property/category
partition.

| Element     | Definition                                              |
|-------------|---------------------------------------------------------|
| Partition   | PropertyRef, CategoryID                                 |
| Order       | DateRaised ASC                                          |
| Function    | ROW_NUMBER()                                            |
| Output      | 1 for the first job in that category at that property,  |
|             | incrementing for each subsequent job                    |
| NULL        | Never NULL -- ROW_NUMBER() always produces an integer   |

---

### DaysSincePreviousJob (within-category gap)

Days elapsed between consecutive jobs at the same property in the same
category.

| Element     | Definition                                              |
|-------------|---------------------------------------------------------|
| Partition   | PropertyRef, CategoryID                                 |
| Order       | DateRaised ASC                                          |
| Function    | LAG(DateRaised, 1) OVER (partition/order)               |
| Numerator   | DateRaised of current row                               |
| Denominator | DateRaised of previous row in partition                 |
| Formula     | DATEDIFF(day, LAG(DateRaised), DateRaised)              |
| NULL        | NULL for JobSequence = 1 (no previous job in category)  |
| Unit        | Calendar days                                           |

Calendar days are used throughout this view. Working day conversion is
available via dbo.fn_WorkingDaysBetween but is not applied here --
the consuming layer applies SLA thresholds and can invoke the function
if needed.

---

### DaysSincePreviousAnyJob (cross-category gap)

Days elapsed between consecutive jobs at the same property regardless
of category.

| Element     | Definition                                              |
|-------------|---------------------------------------------------------|
| Partition   | PropertyRef                                             |
| Order       | DateRaised ASC, JobID ASC (tiebreak)                    |
| Function    | LAG(DateRaised, 1) OVER (partition/order)               |
| Formula     | DATEDIFF(day, LAG(DateRaised), DateRaised)              |
| NULL        | NULL for the first job at that property (no prior job   |
|             | of any category exists)                                 |
| Unit        | Calendar days                                           |

JobID is included as a tiebreak in the ORDER BY to produce a
deterministic sequence when two jobs at the same property share a
DateRaised. Without it, LAG() results are non-deterministic on ties.

---

### PreviousCategoryName / PreviousCategoryGroup (cross-category context)

Category identity of the immediately preceding job at the same property,
regardless of category. Enables the consumer to identify cross-category
patterns without a self-join.

| Element     | Definition                                              |
|-------------|---------------------------------------------------------|
| Partition   | PropertyRef                                             |
| Order       | DateRaised ASC, JobID ASC (tiebreak -- matches above)   |
| Function    | LAG(CategoryName/CategoryGroup, 1) OVER (partition)     |
| NULL        | NULL for the first job at that property                 |

---

## Output Columns

| Column                    | Type         | Source / Notes                        |
|---------------------------|--------------|---------------------------------------|
| JobID                     | INT          | RepairJobs.JobID                      |
| PropertyRef               | VARCHAR      | RepairJobs.PropertyRef                |
| CategoryID                | INT          | RepairCategories.CategoryID           |
| CategoryName              | VARCHAR      | RepairCategories.CategoryName         |
| CategoryGroup             | VARCHAR      | RepairCategories.CategoryGroup        |
| DateRaised                | DATE         | RepairJobs.DateRaised                 |
| Priority                  | VARCHAR      | RepairJobs.Priority                   |
| Status                    | VARCHAR      | RepairJobs.Status                     |
| ContractorID              | INT          | RepairJobs.ContractorID               |
| JobSequence               | INT          | ROW_NUMBER() within PropertyRef +     |
|                           |              | CategoryID                            |
| DaysSincePreviousJob      | INT / NULL   | Calendar days since previous job in   |
|                           |              | same category at same property.       |
|                           |              | NULL for first job in category.       |
| DaysSincePreviousAnyJob   | INT / NULL   | Calendar days since previous job of   |
|                           |              | any category at same property.        |
|                           |              | NULL for first job at property.       |
| PreviousCategoryName      | VARCHAR/NULL | CategoryName of the preceding job at  |
|                           |              | same property (any category).         |
|                           |              | NULL for first job at property.       |
| PreviousCategoryGroup     | VARCHAR/NULL | CategoryGroup of the preceding job.   |
|                           |              | NULL for first job at property.       |

---

## Design Principles

- **No threshold logic in the view.** Gap values are raw calendar day
  counts. Thresholds, flags, and RAG status belong in the consuming
  layer where business context is available.
- **Deterministic ordering.** JobID tiebreak on all window functions
  ordered by DateRaised to prevent non-deterministic LAG() results
  on same-day jobs at the same property.
- **Category-agnostic scope.** All categories and groups are included.
  The consumer filters to the categories relevant to their question.
- **Calendar days throughout.** Working day conversion is not applied
  in the view. The consuming layer may call fn_WorkingDaysBetween
  where a working-day gap is analytically meaningful.
- **NULL means no prior job, not zero.** A NULL gap on the first job
  in a sequence is semantically correct. Zero would imply a prior job
  existed with no elapsed time.
- **No hardcoded values.** Category groupings are read from
  RepairCategories.CategoryGroup, not filtered by string literals
  in the view body.
- **Built for audit readiness.** Full job context (Priority, Status,
  ContractorID) is carried per row so a consumer can reconstruct
  any sequence without additional joins.

---

## Example Calls

```sql
-- All repeat jobs (any category, any gap)
SELECT *
FROM dbo.vw_RepeatRepairs
WHERE JobSequence > 1;

-- Within-category repeats: Damp/Mould jobs returning to same property within 90 days
SELECT *
FROM dbo.vw_RepeatRepairs
WHERE CategoryGroup          = 'Damp/Mould'
  AND JobSequence            > 1
  AND DaysSincePreviousJob  <= 90;

-- Cross-category causal chain: Structural or Plumbing job preceding Damp/Mould within 90 days
SELECT *
FROM dbo.vw_RepeatRepairs
WHERE CategoryGroup             = 'Damp/Mould'
  AND PreviousCategoryGroup     IN ('Structural', 'Plumbing')
  AND DaysSincePreviousAnyJob  <= 90
ORDER BY DaysSincePreviousAnyJob ASC;

-- Full sequence for a specific property
SELECT *
FROM dbo.vw_RepeatRepairs
WHERE PropertyRef = 'PROP0042'
ORDER BY DateRaised, JobID;
```

---