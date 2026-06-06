USE RotherhamHousingRepairs;
GO

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
    , CASE WHEN rc.CategoryGroup = 'Damp/Mould' THEN 1 ELSE 0 END AS IsAwaabiJob
    , CASE
        WHEN r.Priority = 'Emergency'     AND r.DaysToComplete <= 1  THEN 1
        WHEN r.Priority = 'Emergency'     AND r.DaysToComplete > 1   THEN 0
      END AS EmergencyOnTarget
    , CASE
        WHEN r.Priority = 'Urgent'        AND r.DaysToComplete <= 14 THEN 1
        WHEN r.Priority = 'Urgent'        AND r.DaysToComplete > 14  THEN 0
      END AS UrgentOnTarget
    , CASE
        WHEN r.Priority = 'Non-Emergency' AND r.DaysToComplete <= 20 THEN 1
        WHEN r.Priority = 'Non-Emergency' AND r.DaysToComplete > 20  THEN 0
      END AS NonEmergencyOnTarget
FROM dbo.RepairJobs r
    INNER JOIN dbo.Properties p       ON r.PropertyRef  = p.PropertyRef
    INNER JOIN dbo.WardGeometry wg    ON p.WardID       = wg.WardID
    INNER JOIN dbo.RepairCategories rc ON r.CategoryID  = rc.CategoryID
    INNER JOIN dbo.Contractors c       ON r.ContractorID = c.ContractorID
    INNER JOIN dbo.Calendar cal        ON r.DateRaised   = cal.CalendarDate;
GO