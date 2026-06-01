USE RotherhamHousingRepairs;
GO

/*
Procedure:	dbo.GetRepairsByCategory
Author:		Martin Sefelin
Co-Author:	Claude (Anthropic)
Created:	June 2026
Version:	1.1
Purpose:	Category-level KPI reporting for housing repairs service.
		Returns job volumes, response time compliance, Awaab's Law RAG,
		no access rates, repeat damp property detection and seasonal split
		per category and contractor.
Notes:		Defaults to 2025/26 financial year to align with synthetic dataset.
		Awaab's Law thresholds and seasonal window are parameterised --
		no code change needed for policy updates.
		Two staging tables used deliberately -- repeat damp logic operates
		at property grain, all other metrics at category/contractor grain.
		Built against synthetic data -- see DISCLAIMER.md.
*/

CREATE OR ALTER PROCEDURE dbo.GetRepairsByCategory
(
      @CategoryGroup          VARCHAR(50)  = NULL
    , @ContractorName         VARCHAR(100) = NULL
    , @DateFrom               DATE         = NULL
    , @DateTo                 DATE         = NULL

    -- Awaab's Law response thresholds (days) -- legal obligations, not KPI targets
    , @AwaabsEmergencyDays    INT          = 1
    , @AwaabsUrgentDays       INT          = 14
    , @AwaabsRoutineDays      INT          = 90

    -- Seasonal window (month numbers) -- defaults to November through March
    , @WinterMonthStart       INT          = 11
    , @WinterMonthEnd         INT          = 3
)
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
		-- Last fiscal year used here to align with the synthetic dataset.
        IF @DateFrom IS NULL SET @DateFrom = '2025-04-01' --DATEFROMPARTS(YEAR(GETDATE()) - 1, 4, 1);
        IF @DateTo   IS NULL SET @DateTo   = '2026-03-31' --DATEFROMPARTS(YEAR(GETDATE()), 3, 31);

        IF @DateFrom > @DateTo
            THROW 50001, 'DateFrom cannot be later than DateTo.', 1;

        IF @WinterMonthStart NOT BETWEEN 1 AND 12
            OR @WinterMonthEnd NOT BETWEEN 1 AND 12
            THROW 50002, 'WinterMonthStart and WinterMonthEnd must be valid month numbers (1-12).', 1;


        -- Stage category/contractor metrics before RAG evaluation.
        -- Awaab's compliance pre-calculated here so the RAG CASE below
        -- references a single column rather than repeating the expression.
        DROP TABLE IF EXISTS #CategoryMetrics;

        SELECT
              rc.CategoryGroup
            , rc.CategoryName
            , c.ContractorName
            , @DateFrom                                     AS PeriodFrom
            , @DateTo                                       AS PeriodTo
            , IIF(rc.CategoryGroup = 'Damp/Mould', 1, 0)   AS IsDampMould
            , COUNT(r.JobID)                                AS TotalJobs

            -- AVG and MAX reflect completed jobs only -- DaysToComplete is NULL for unresolved jobs
            , ROUND(AVG(CAST(r.DaysToComplete AS FLOAT)), 1) AS AvgDaysToComplete
            , MAX(r.DaysToComplete)                          AS MaxDaysToComplete

            -- Priority-aware compliance: each job measured against its own threshold band
            , SUM(CASE
                    WHEN r.Status = 'Completed'
                     AND (   (r.Priority = 'Emergency'     AND r.DaysToComplete <= @AwaabsEmergencyDays)
                          OR (r.Priority = 'Urgent'        AND r.DaysToComplete <= @AwaabsUrgentDays)
                          OR (r.Priority = 'Non-Emergency' AND r.DaysToComplete <= @AwaabsRoutineDays))
                    THEN 1 ELSE 0
                  END)                                       AS JobsCompletedWithinTarget

            , ROUND(
                100.0 * SUM(CASE
                              WHEN r.Status = 'Completed'
                               AND (   (r.Priority = 'Emergency'     AND r.DaysToComplete <= @AwaabsEmergencyDays)
                                    OR (r.Priority = 'Urgent'        AND r.DaysToComplete <= @AwaabsUrgentDays)
                                    OR (r.Priority = 'Non-Emergency' AND r.DaysToComplete <= @AwaabsRoutineDays))
                              THEN 1 ELSE 0
                            END)
                / NULLIF(SUM(IIF(r.Status = 'Completed', 1, 0)), 0)
              , 1)                                           AS CompliancePct

            , SUM(IIF(r.Status = 'No Access', 1, 0))         AS NoAccessJobs

            , ROUND(
                100.0 * SUM(IIF(r.Status = 'No Access', 1, 0))
                / NULLIF(COUNT(r.JobID), 0)
              , 1)                                           AS NoAccessPct

            -- Damp-only compliance figures staged here for clean RAG evaluation below
            , SUM(CASE
                    WHEN rc.CategoryGroup = 'Damp/Mould'
                     AND r.Status = 'Completed'
                     AND (   (r.Priority = 'Emergency'     AND r.DaysToComplete <= @AwaabsEmergencyDays)
                          OR (r.Priority = 'Urgent'        AND r.DaysToComplete <= @AwaabsUrgentDays)
                          OR (r.Priority = 'Non-Emergency' AND r.DaysToComplete <= @AwaabsRoutineDays))
                    THEN 1 ELSE 0
                  END)                                       AS DampAwaabsCompliantJobs

            , SUM(IIF(rc.CategoryGroup = 'Damp/Mould'
                      AND r.Status = 'Completed', 1, 0))     AS DampCompletedJobs

            -- Cross-year winter window (e.g. Nov-Mar) requires OR rather than BETWEEN
            , SUM(CASE
                    WHEN @WinterMonthStart > @WinterMonthEnd
                        THEN IIF(MONTH(r.DateRaised) >= @WinterMonthStart
                                 OR MONTH(r.DateRaised) <= @WinterMonthEnd, 1, 0)
                    ELSE IIF(MONTH(r.DateRaised) BETWEEN @WinterMonthStart
                                                     AND @WinterMonthEnd, 1, 0)
                  END)                                       AS WinterJobs

            , SUM(CASE
                    WHEN @WinterMonthStart > @WinterMonthEnd
                        THEN IIF(MONTH(r.DateRaised) >= @WinterMonthStart
                                 OR MONTH(r.DateRaised) <= @WinterMonthEnd, 0, 1)
                    ELSE IIF(MONTH(r.DateRaised) BETWEEN @WinterMonthStart
                                                     AND @WinterMonthEnd, 0, 1)
                  END)                                       AS SummerJobs

        INTO #CategoryMetrics

        FROM dbo.RepairJobs r
            INNER JOIN dbo.Contractors c
                ON r.ContractorID = c.ContractorID
            INNER JOIN dbo.RepairCategories rc
                ON r.CategoryID = rc.CategoryID

        WHERE
            (@CategoryGroup   IS NULL OR rc.CategoryGroup  = @CategoryGroup)
            AND (@ContractorName IS NULL OR c.ContractorName = @ContractorName)
            AND r.DateRaised BETWEEN @DateFrom AND @DateTo

        GROUP BY
              rc.CategoryGroup
            , rc.CategoryName
            , c.ContractorName;


        -- Repeat damp detection at property grain.
        -- Kept separate from #CategoryMetrics because property-level aggregation
        -- cannot be merged cleanly with category/contractor aggregation.
        DROP TABLE IF EXISTS #RepeatDampProperties;

        SELECT
              rc.CategoryName
            , c.ContractorName
            , COUNT(DISTINCT r.PropertyRef)                 AS TotalDampProperties
            , SUM(IIF(pjc.JobsAtProperty > 1, 1, 0))        AS PropertiesWithRepeatDampJobs

        INTO #RepeatDampProperties

        FROM dbo.RepairJobs r
            INNER JOIN dbo.Contractors c
                ON r.ContractorID = c.ContractorID
            INNER JOIN dbo.RepairCategories rc
                ON r.CategoryID = rc.CategoryID
            INNER JOIN (
                -- Count damp jobs per property per contractor within the period
                SELECT r2.PropertyRef, r2.ContractorID, COUNT(r2.JobID) AS JobsAtProperty
                FROM dbo.RepairJobs r2
                    INNER JOIN dbo.RepairCategories rc2 ON r2.CategoryID = rc2.CategoryID
                WHERE rc2.CategoryGroup = 'Damp/Mould'
                  AND r2.DateRaised BETWEEN @DateFrom AND @DateTo
                GROUP BY r2.PropertyRef, r2.ContractorID
            ) AS pjc
                ON  r.PropertyRef  = pjc.PropertyRef
                AND r.ContractorID = pjc.ContractorID

        WHERE
            rc.CategoryGroup = 'Damp/Mould'
            AND r.DateRaised BETWEEN @DateFrom AND @DateTo
            AND (@ContractorName IS NULL OR c.ContractorName = @ContractorName)

        GROUP BY
              rc.CategoryName
            , c.ContractorName;


        -- RAG evaluation and final output.
        -- Awaab's and repeat damp columns are NULL for non-damp rows -- not applicable,
        -- not zero. NULL and zero are not interchangeable in audit or BI aggregations.
        -- Thresholds exposed in output to make result sets self-documenting.
        SELECT
              cm.CategoryGroup
            , cm.CategoryName
            , cm.ContractorName
            , cm.PeriodFrom
            , cm.PeriodTo
            , cm.TotalJobs
            , cm.IsDampMould
            , cm.AvgDaysToComplete
            , cm.MaxDaysToComplete
            , cm.JobsCompletedWithinTarget
            , cm.CompliancePct
            , cm.NoAccessJobs
            , cm.NoAccessPct

            -- Awaab's RAG: Damp/Mould rows only, NULL elsewhere
            , CASE
                WHEN cm.IsDampMould = 0      THEN NULL
                WHEN cm.DampCompletedJobs = 0 THEN NULL
                WHEN ROUND(100.0 * cm.DampAwaabsCompliantJobs
                           / NULLIF(cm.DampCompletedJobs, 0), 1) >= 100 THEN 'Green'
                WHEN ROUND(100.0 * cm.DampAwaabsCompliantJobs
                           / NULLIF(cm.DampCompletedJobs, 0), 1) >= 90  THEN 'Amber'
                ELSE 'Red'
              END AS AwaabsRAG

            -- ComplianceFlag as BIT for easier BI filtering than parsing the RAG string
            , CASE
                WHEN cm.IsDampMould = 0       THEN NULL
                WHEN cm.DampCompletedJobs = 0  THEN NULL
                WHEN cm.DampAwaabsCompliantJobs = cm.DampCompletedJobs THEN CAST(1 AS BIT)
                ELSE CAST(0 AS BIT)
              END AS ComplianceFlag

            , rdp.PropertiesWithRepeatDampJobs
            , rdp.TotalDampProperties
            , ROUND(100.0 * rdp.PropertiesWithRepeatDampJobs
                    / NULLIF(rdp.TotalDampProperties, 0), 1) AS RepeatDampPct

            , cm.WinterJobs
            , cm.SummerJobs
            , ROUND(100.0 * cm.WinterJobs / NULLIF(cm.TotalJobs, 0), 1) AS WinterPct

            , @AwaabsEmergencyDays  AS AwaabsEmergencyDays
            , @AwaabsUrgentDays     AS AwaabsUrgentDays
            , @AwaabsRoutineDays    AS AwaabsRoutineDays
            , @WinterMonthStart     AS WinterMonthStart
            , @WinterMonthEnd       AS WinterMonthEnd
            , GETDATE()             AS ReportTimestamp

        FROM #CategoryMetrics cm
            LEFT JOIN #RepeatDampProperties rdp
                ON  cm.CategoryName   = rdp.CategoryName
                AND cm.ContractorName = rdp.ContractorName

        ORDER BY
              cm.CategoryGroup
            , cm.CategoryName
            , cm.ContractorName;

        DROP TABLE IF EXISTS #CategoryMetrics;
        DROP TABLE IF EXISTS #RepeatDampProperties;

    END TRY

    BEGIN CATCH

        DECLARE @ErrorMessage  NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState    INT;

        SELECT
              @ErrorMessage  = ERROR_MESSAGE()
            , @ErrorSeverity = ERROR_SEVERITY()
            , @ErrorState    = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);

    END CATCH

END;
GO
