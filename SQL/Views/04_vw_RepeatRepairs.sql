USE RotherhamHousingRepairs;
GO

/*
=======================================================================
View:       dbo.vw_RepeatRepairs
Author:     Martin Sefelin
Version:    v1.0
Created:    2026-06-16

Purpose:
    Surfaces consecutive repair job sequences at property level to
    support Awaab's Law compliance monitoring and root cause analysis.

    Two gap signals are calculated per row:

    DaysSincePreviousJob
        Days since the previous job at the same property in the same
        category (calendar days). Primary within-category repeat signal.
        NULL for the first job in that category at that property.

    DaysSincePreviousAnyJob
        Days since the previous job at the same property regardless of
        category. Enables cross-category pattern detection -- e.g. a
        Structural job followed by Damp/Mould at the same property.
        NULL for the first job of any kind at that property.

    No threshold logic is applied here. Gap interpretation belongs in
    the consuming layer where business context is available. Hardcoding
    a threshold in the view would produce misleading signals without
    cross-category awareness.

Notes:
    - JobID is used as a tiebreak in all window ORDER BY clauses to
      produce deterministic results when two jobs share a DateRaised
      at the same property. Without it, LAG() is non-deterministic
      on ties.
    - Calendar days are used throughout. The consuming layer may call
      dbo.fn_WorkingDaysBetween where a working-day gap is needed.
    - NULL means no prior job exists -- semantically correct. Zero
      would imply a prior job with no elapsed time.
=======================================================================
*/

CREATE OR ALTER VIEW dbo.vw_RepeatRepairs
AS

WITH JobsWithContext AS
(
    SELECT
          r.JobID
        , r.PropertyRef
        , r.CategoryID
        , rc.CategoryName
        , rc.CategoryGroup
        , r.DateRaised
        , r.Priority
        , r.Status
        , r.ContractorID

        /*
        Within-category sequence number.
        Resets to 1 for each property/category combination.
        JobID tiebreak ensures deterministic ordering on same-day raises.
        */
        , ROW_NUMBER() OVER (
            PARTITION BY r.PropertyRef, r.CategoryID
            ORDER BY r.DateRaised ASC, r.JobID ASC
          )                                                      AS JobSequence

        /*
        Previous job date within the same property and category.
        NULL on the first job in each partition -- DATEDIFF below
        produces NULL correctly without a separate guard.
        */
        , LAG(r.DateRaised) OVER (
            PARTITION BY r.PropertyRef, r.CategoryID
            ORDER BY r.DateRaised ASC, r.JobID ASC
          )                                                      AS PreviousJobDate

        /*
        Previous job date across all categories at the same property.
        NULL on the first job at each property.
        */
        , LAG(r.DateRaised) OVER (
            PARTITION BY r.PropertyRef
            ORDER BY r.DateRaised ASC, r.JobID ASC
          )                                                      AS PreviousAnyJobDate

        /*
        Category identity of the previous job at this property
        (any category). Carried so the consumer can identify
        cross-category patterns without a self-join.
        NULL on the first job at each property.
        */
        , LAG(rc.CategoryName) OVER (
            PARTITION BY r.PropertyRef
            ORDER BY r.DateRaised ASC, r.JobID ASC
          )                                                      AS PreviousCategoryName

        , LAG(rc.CategoryGroup) OVER (
            PARTITION BY r.PropertyRef
            ORDER BY r.DateRaised ASC, r.JobID ASC
          )                                                      AS PreviousCategoryGroup

    FROM dbo.RepairJobs           r
        INNER JOIN dbo.RepairCategories rc ON r.CategoryID = rc.CategoryID
)

SELECT
      JobID
    , PropertyRef
    , CategoryID
    , CategoryName
    , CategoryGroup
    , DateRaised
    , Priority
    , Status
    , ContractorID
    , JobSequence
    , DATEDIFF(day, PreviousJobDate,    DateRaised) AS DaysSincePreviousJob
    , DATEDIFF(day, PreviousAnyJobDate, DateRaised) AS DaysSincePreviousAnyJob
    , PreviousCategoryName
    , PreviousCategoryGroup

FROM JobsWithContext;
GO
