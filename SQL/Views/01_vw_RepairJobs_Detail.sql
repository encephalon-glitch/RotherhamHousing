USE RotherhamHousingRepairs;
GO

/*
=======================================================================
View:       dbo.vw_RepairJobs_Detail
Author:     Martin Sefelin
Version:    1.1
Changed:    2026-06-26

Purpose:
    Fully joined row-level detail view across RepairJobs, Properties,
    WardGeometry, RepairCategories, Contractors and Calendar. Primary
    source for ad-hoc analysis, Plotly visualisation, and the Power BI
    semantic layer.

Change log:
	v1.1    NonEmergencyOnTarget corrected to evaluate against working
            days via dbo.fn_WorkingDaysBetween, consistent with
            GetContractorPerformance v1.5 and GetRepairsByCategory v1.2.
            The v1.0 calendar-day evaluation systematically overstated
            Non-Emergency compliance relative to both stored procedures,
            which had already been fixed. WorkingDaysToComplete added
            as an explicit output column -- NULL for Emergency/Urgent
            rows, since those thresholds are calendar days by
            legislative definition and must not carry a working-day
            reading. CROSS APPLY used so fn_WorkingDaysBetween is
            called once per row rather than repeated inline across two
            expressions. IsAwaabiJob renamed to IsAwaabJob -- typo, no
            downstream dependency on the old name at time of fix.
	v1.0    Initial build. No version header. NonEmergencyOnTarget
            evaluated against DaysToComplete (calendar days) -- did
            not reflect the 20-working-day SLA convention.

Notes:
    - Emergency (1 day) and Urgent (14 days) thresholds are calendar
      days under Awaab's Law -- legislative definitions, apply
      regardless of weekends or bank holidays. Evaluated directly
      against DaysToComplete.
    - Non-Emergency (20 days) is a council KPI convention, evaluated
      in working days. Evaluated against the CROSS APPLY working-day
      count, not DaysToComplete.
    - fn_WorkingDaysBetween returns NULL when DateCompleted is NULL,
      so incomplete Non-Emergency jobs correctly fall out of
      NonEmergencyOnTarget without an additional status guard.
    - WorkingDaysToComplete is NULL for Emergency and Urgent rows by
      design, not an omission. Surfacing a working-day figure for a
      priority band governed by a calendar-day legal threshold would
      imply a reading that does not apply.
=======================================================================
*/

CREATE OR ALTER VIEW dbo.vw_RepairJobs_Detail AS
SELECT
      r.JobID
    , r.PropertyRef
    , wg.WD24CD
    , wg.WD24NM
    , p.PropertyType
    , p.BedroomCount
    , p.EPC_Rating
    , p.BuildYear
    , p.IsDecent
    , rc.CategoryName
    , rc.CategoryGroup
    , r.Priority
    , r.DateRaised
    , r.DateCompleted
    , r.DaysToComplete

    -- Working days, Non-Emergency only. NULL for Emergency/Urgent -- those
    -- bands are legislated in calendar days and must not carry a working-day
    -- reading alongside it.
	, IIF(r.Priority = 'Non-Emergency', wdc.WD, NULL) AS WorkingDaysToComplete
    , r.Status
    , r.RightFirstTime
    , r.TenantSatisfactionScore
    , c.ContractorName
    , c.ContractType
    , cal.MonthName
    , cal.MonthNum
    , cal.Quarter
    , cal.FinancialYear
    , cal.IsWorkingDay
    , CASE WHEN rc.CategoryGroup = 'Damp/Mould' THEN 1 ELSE 0 END AS IsAwaabJob

    , CASE
        WHEN r.Priority = 'Emergency'     AND r.DaysToComplete <= 1  THEN 1
        WHEN r.Priority = 'Emergency'     AND r.DaysToComplete > 1   THEN 0
      END AS EmergencyOnTarget

    , CASE
        WHEN r.Priority = 'Urgent'        AND r.DaysToComplete <= 14 THEN 1
        WHEN r.Priority = 'Urgent'        AND r.DaysToComplete > 14  THEN 0
      END AS UrgentOnTarget

    -- Working days, not DaysToComplete. v1.0 evaluated this against calendar
    -- days, which overstated compliance relative to both stored procedures.
    , CASE
        WHEN r.Priority = 'Non-Emergency' AND wdc.WD <= 20 THEN 1
        WHEN r.Priority = 'Non-Emergency' AND wdc.WD > 20  THEN 0
      END AS NonEmergencyOnTarget

FROM dbo.RepairJobs r
    INNER JOIN dbo.Properties p        ON r.PropertyRef  = p.PropertyRef
    INNER JOIN dbo.WardGeometry wg     ON p.WardID        = wg.WardID
    INNER JOIN dbo.RepairCategories rc ON r.CategoryID    = rc.CategoryID
    INNER JOIN dbo.Contractors c       ON r.ContractorID  = c.ContractorID
    INNER JOIN dbo.Calendar cal        ON r.DateRaised    = cal.CalendarDate
    CROSS APPLY (
        -- Computed once per row regardless of priority. Cheap (single Calendar
        -- scan) and avoids repeating the expression in both WorkingDaysToComplete
        -- and NonEmergencyOnTarget.
        SELECT dbo.fn_WorkingDaysBetween(r.DateRaised, r.DateCompleted) AS WD
    ) wdc;
GO
