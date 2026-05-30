USE RotherhamHousingRepairs;
GO

-- ============================================================
-- VIEW 2: KPI summary by month and contractor
-- Aggregates performance against Rotherham's published targets
-- Emergency: 98% | Non-Emergency: 94% | RFT: 93%
-- ============================================================
CREATE VIEW vw_KPI_Summary AS
SELECT
    cal.FinancialYear,
    cal.Quarter,
    cal.MonthName,
    cal.MonthNum,
    c.ContractorName,
    -- Volume
    COUNT(r.JobID) AS TotalJobs,
    SUM(CASE WHEN r.Priority = 'Emergency' THEN 1 ELSE 0 END) AS EmergencyJobs,
    SUM(CASE WHEN r.Priority = 'Non-Emergency' THEN 1 ELSE 0 END) AS NonEmergencyJobs,
    -- Emergency completion rate vs 98% target
    ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Emergency'
                    AND r.Status = 'Completed'
                    AND r.DaysToComplete <= 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Emergency' THEN 1 ELSE 0 END), 0)
    , 1) AS EmergencyCompletionPct,
    -- Non-emergency completion rate vs 94% target
    ROUND(
        100.0 * SUM(CASE WHEN r.Priority = 'Non-Emergency'
                    AND r.Status = 'Completed'
                    AND r.DaysToComplete <= 20 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.Priority = 'Non-Emergency' THEN 1 ELSE 0 END), 0)
    , 1) AS NonEmergencyCompletionPct,
    -- Right first time vs 93% target
    ROUND(
        100.0 * SUM(CASE WHEN r.RightFirstTime = 1 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN r.RightFirstTime IS NOT NULL THEN 1 ELSE 0 END), 0)
    , 1) AS RightFirstTimePct,
    -- Average tenant satisfaction
    ROUND(AVG(CAST(r.TenantSatisfactionScore AS FLOAT)), 2) AS AvgSatisfaction,
    -- Awaabs Law: damp and mould jobs
    SUM(CASE WHEN rc.CategoryGroup = 'Damp/Mould' THEN 1 ELSE 0 END) AS DampMouldJobs
FROM RepairJobs r
JOIN Contractors c ON r.ContractorID = c.ContractorID
JOIN RepairCategories rc ON r.CategoryID = rc.CategoryID
JOIN Calendar cal ON r.DateRaised = cal.CalendarDate
GROUP BY
    cal.FinancialYear,
    cal.Quarter,
    cal.MonthNum,
    cal.MonthName,
    c.ContractorName;
GO