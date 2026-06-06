USE RotherhamHousingRepairs;
GO

-- ============================================================
-- VIEW 2: KPI summary by month and contractor
-- Aggregates performance against Rotherham's published targets
-- Emergency: 98% | Non-Emergency: 94% | RFT: 93%
-- ============================================================

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
    -- Emergency completion rate vs 98% target
    , ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Emergency'
                     AND r.Status = 'Completed'
                     AND r.DaysToComplete <= 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Emergency' THEN 1 ELSE 0 END), 0)
      , 1)                                                                    AS EmergencyCompletionPct
    -- Urgent completion rate vs 14-day Awaab's Law threshold
    , ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Urgent'
                     AND r.Status = 'Completed'
                     AND r.DaysToComplete <= 14 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Urgent' THEN 1 ELSE 0 END), 0)
      , 1)                                                                    AS UrgentCompletionPct
    -- Non-emergency completion rate vs 94% target
    , ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Non-Emergency'
                     AND r.Status = 'Completed'
                     AND r.DaysToComplete <= 20 THEN 1 ELSE 0 END)
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
GROUP BY
      cal.FinancialYear
    , cal.Quarter
    , cal.MonthNum
    , cal.MonthName
    , c.ContractorName;
GO