USE RotherhamHousingRepairs;
GO

/*
=======================================================================
View:       dbo.vw_KPI_Summary
Author:     Martin Sefelin
Version:    1.1
Changed:    2026-06-26

Purpose:
    KPI summary aggregated by month and contractor, against Rotherham's
    published targets -- Emergency 98%, Non-Emergency 94%, RFT 93%.

Change log:
	v1.1    NonEmergencyCompletionPct corrected to evaluate against
            working days via dbo.fn_WorkingDaysBetween, consistent with
            GetContractorPerformance v1.5, GetRepairsByCategory v1.2
            and vw_RepairJobs_Detail v1.1. The v1.0 calendar-day
            evaluation systematically overstated Non-Emergency
            compliance relative to all three. CROSS APPLY computes the
            working-day count once per underlying row, before GROUP BY
            collapses to month/contractor grain.
	v1.0    Initial build. No version header. NonEmergencyCompletionPct
            evaluated against DaysToComplete (calendar days) -- did not
            reflect the 20-working-day SLA convention.

Notes:
    - Emergency (1 day) and Urgent (14 days) thresholds are calendar
      days under Awaab's Law -- legislative definitions, apply
      regardless of weekends or bank holidays. Evaluated directly
      against DaysToComplete.
    - Non-Emergency (20 days) is a council KPI convention, evaluated
      in working days. Evaluated against the CROSS APPLY working-day
      count, not DaysToComplete.
    - fn_WorkingDaysBetween returns NULL when DateCompleted is NULL,
      so incomplete Non-Emergency jobs correctly fall out of the
      numerator without an additional status guard.
=======================================================================
*/

CREATE OR ALTER VIEW dbo.vw_KPI_Summary AS
SELECT
      cal.FinancialYear
    , cal.Quarter
    , cal.MonthName
    , cal.MonthNum
    , c.ContractorName
    -- Volume
    , COUNT(r.JobID)                                                          AS TotalJobs
    , SUM(CASE WHEN r.Priority = 'Emergency'     THEN 1 ELSE 0 END)          AS EmergencyJobs
    , SUM(CASE WHEN r.Priority = 'Urgent'        THEN 1 ELSE 0 END)          AS UrgentJobs
    , SUM(CASE WHEN r.Priority = 'Non-Emergency' THEN 1 ELSE 0 END)          AS NonEmergencyJobs
    -- Emergency completion rate vs 98% target -- calendar days, legislative
    , ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Emergency'
                     AND r.Status = 'Completed'
                     AND r.DaysToComplete <= 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Emergency' THEN 1 ELSE 0 END), 0)
      , 1)                                                                    AS EmergencyCompletionPct
    -- Urgent completion rate vs 14-day Awaab's Law threshold -- calendar days, legislative
    , ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Urgent'
                     AND r.Status = 'Completed'
                     AND r.DaysToComplete <= 14 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Urgent' THEN 1 ELSE 0 END), 0)
      , 1)                                                                    AS UrgentCompletionPct
    -- Non-emergency completion rate vs 94% target -- working days, council convention.
    -- wdc.WD sourced from fn_WorkingDaysBetween, not DaysToComplete (calendar days),
    -- which would silently overstate compliance against a working-day target.
    , ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Non-Emergency'
                     AND r.Status = 'Completed'
                     AND wdc.WD <= 20 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Non-Emergency' THEN 1 ELSE 0 END), 0)
      , 1)                                                                    AS NonEmergencyCompletionPct
    -- Right first time vs 93% target
    , ROUND(
        100.0 * SUM(CASE WHEN r.RightFirstTime = 1           THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.RightFirstTime IS NOT NULL   THEN 1 ELSE 0 END), 0)
      , 1)                                                                    AS RightFirstTimePct
    , ROUND(AVG(CAST(r.TenantSatisfactionScore AS FLOAT)), 2)                AS AvgSatisfaction
    , SUM(CASE WHEN rc.CategoryGroup = 'Damp/Mould' THEN 1 ELSE 0 END)      AS DampMouldJobs
FROM dbo.RepairJobs r
    INNER JOIN dbo.Contractors c        ON r.ContractorID = c.ContractorID
    INNER JOIN dbo.RepairCategories rc  ON r.CategoryID   = rc.CategoryID
    INNER JOIN dbo.Calendar cal         ON r.DateRaised   = cal.CalendarDate
    CROSS APPLY (
        -- Computed once per underlying row, before GROUP BY collapses to
        -- month/contractor grain. Cheap (single Calendar scan per row) and
        -- avoids repeating the expression elsewhere in the aggregation.
        SELECT dbo.fn_WorkingDaysBetween(r.DateRaised, r.DateCompleted) AS WD
    ) wdc
GROUP BY
      cal.FinancialYear
    , cal.Quarter
    , cal.MonthNum
    , cal.MonthName
    , c.ContractorName;
GO
