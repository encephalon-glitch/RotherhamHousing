USE RotherhamHousingRepairs;
GO

-- ============================================================
-- VIEW 1: Clean joined dataset
-- Brings together all dimensions with the fact table
-- Foundation for all reporting queries
-- ============================================================
CREATE VIEW vw_RepairJobs_Detail AS
SELECT
    r.JobID,
    r.PropertyRef,
    p.Ward,
    p.PropertyType,
    p.BedroomCount,
    p.EPC_Rating,
    p.BuildYear,
    p.IsDecent,
    rc.CategoryName,
    rc.CategoryGroup,
    r.Priority,
    r.DateRaised,
    r.DateCompleted,
    r.DaysToComplete,
    r.Status,
    r.RightFirstTime,
    r.TenantSatisfactionScore,
    c.ContractorName,
    c.ContractType,
    cal.MonthName,
    cal.MonthNum,
    cal.Quarter,
    cal.FinancialYear,
    cal.IsWorkingDay,
    -- Awaabs Law flag: damp/mould jobs
    CASE WHEN rc.CategoryGroup = 'Damp/Mould' THEN 1 ELSE 0 END AS IsAwaabiJob,
    -- Target compliance flags
    CASE
        WHEN r.Priority = 'Emergency' AND r.DaysToComplete <= 1 THEN 1
        WHEN r.Priority = 'Emergency' AND r.DaysToComplete > 1 THEN 0
        ELSE NULL
    END AS EmergencyOnTarget,
    CASE
        WHEN r.Priority = 'Non-Emergency' AND r.DaysToComplete <= 20 THEN 1
        WHEN r.Priority = 'Non-Emergency' AND r.DaysToComplete > 20 THEN 0
        ELSE NULL
    END AS NonEmergencyOnTarget
FROM RepairJobs r
JOIN Properties p ON r.PropertyRef = p.PropertyRef
JOIN RepairCategories rc ON r.CategoryID = rc.CategoryID
JOIN Contractors c ON r.ContractorID = c.ContractorID
JOIN Calendar cal ON r.DateRaised = cal.CalendarDate;
GO