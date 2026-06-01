USE RotherhamHousingRepairs;
GO

/*
Procedure:	dbo.GetContractorPerformance
Author:		Martin Sefelin
Co-Author:	Claude (Anthropic)
Created:	May 2026
Version:	1.4
Purpose:	Contractor KPI reporting for housing repairs service.
                Returns emergency/non-emergency completion rates, Right
                First Time, tenant satisfaction and Awaab's Law damp and
                mould workload with RAG status against parameterised targets.
Notes:		Defaults to last complete calendar month if no dates supplied.
                KPI targets parameterised -- no code change needed for policy updates.
                Built against synthetic data -- see DISCLAIMER.md.
*/

CREATE OR ALTER PROCEDURE dbo.GetContractorPerformance
(
      @ContractorName              VARCHAR(100) = NULL
    , @DateFrom                    DATE         = NULL
    , @DateTo                      DATE         = NULL

    -- KPI targets default to Rotherham published benchmarks
    , @TargetEmergencyGreen        DECIMAL(5,1) = 98.0
    , @TargetEmergencyAmber        DECIMAL(5,1) = 95.0
    , @TargetNonEmergencyGreen     DECIMAL(5,1) = 94.0
    , @TargetNonEmergencyAmber     DECIMAL(5,1) = 90.0
    , @TargetRFTGreen              DECIMAL(5,1) = 93.0
    , @TargetRFTAmber              DECIMAL(5,1) = 90.0
)
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY

        -- Production default: last complete calendar month.
        -- Last fiscal year used here to align with the synthetic dataset.
        IF @DateFrom IS NULL
            SET @DateFrom =	'2025-04-01'	--DATEFROMPARTS(YEAR(GETDATE()) - 1, 4, 1);

        IF @DateTo IS NULL
            SET @DateTo =	'2026-03-31'	--DATEFROMPARTS(YEAR(GETDATE()), 3, 31);

        -- Catch accidental parameter inversion before hitting the data
        IF @DateFrom > @DateTo
            THROW 50001, 'DateFrom cannot be later than DateTo.', 1;


        -- Stage calculated metrics before RAG evaluation.
        -- Separating calculation from RAG logic prevents repeated expressions
        -- and makes future target changes easier to test and audit.
        DROP TABLE IF EXISTS #ContractorMetrics;

        SELECT
              c.ContractorName
            , @DateFrom AS PeriodFrom
            , @DateTo   AS PeriodTo
            , COUNT(r.JobID) AS TotalJobs
            , SUM(IIF(r.Priority = 'Emergency',     1, 0)) AS EmergencyJobs
            , SUM(IIF(r.Priority = 'Non-Emergency', 1, 0)) AS NonEmergencyJobs

            -- Emergency: target is completion within 1 working day
            , ROUND(
                100.0 * SUM(CASE WHEN r.Priority = 'Emergency'
                                  AND r.Status = 'Completed'
                                  AND r.DaysToComplete <= 1 THEN 1 ELSE 0 END)
                / NULLIF(SUM(IIF(r.Priority = 'Emergency', 1, 0)), 0)
              , 1) AS EmergencyCompletionPct

            -- Non-emergency: target is completion within 20 working days
            , ROUND(
                100.0 * SUM(CASE WHEN r.Priority = 'Non-Emergency'
                                  AND r.Status = 'Completed'
                                  AND r.DaysToComplete <= 20 THEN 1 ELSE 0 END)
                / NULLIF(SUM(IIF(r.Priority = 'Non-Emergency', 1, 0)), 0)
              , 1) AS NonEmergencyCompletionPct

            -- NULLIF guards against division by zero where RightFirstTime
            -- is NULL for non-completed jobs
            , ROUND(
                100.0 * SUM(IIF(r.RightFirstTime = 1,          1, 0))
                / NULLIF(SUM(IIF(r.RightFirstTime IS NOT NULL,  1, 0)), 0)
              , 1) AS RightFirstTimePct

            , ROUND(AVG(CAST(r.TenantSatisfactionScore AS FLOAT)), 2) AS AvgSatisfaction

            -- Awaab's Law (in force Jan 2024): damp and mould response times
            -- are a legal compliance obligation, not just a KPI
            , SUM(IIF(rc.CategoryGroup = 'Damp/Mould', 1, 0)) AS DampMouldJobs

        INTO #ContractorMetrics

        FROM dbo.RepairJobs r
            INNER JOIN dbo.Contractors c
                ON r.ContractorID = c.ContractorID
            INNER JOIN dbo.RepairCategories rc
                ON r.CategoryID = rc.CategoryID

        WHERE
            (@ContractorName IS NULL OR c.ContractorName = @ContractorName)
            AND r.DateRaised BETWEEN @DateFrom AND @DateTo

        GROUP BY c.ContractorName;


        -- RAG evaluation applied against staged metrics.
        -- Thresholds exposed in output to make result sets self-documenting
        -- for audit and BI tool consumption.
        SELECT
              ContractorName
            , PeriodFrom
            , PeriodTo
            , TotalJobs
            , EmergencyJobs
            , NonEmergencyJobs
            , EmergencyCompletionPct
            , NonEmergencyCompletionPct
            , RightFirstTimePct
            , AvgSatisfaction
            , DampMouldJobs

            , CASE
                WHEN EmergencyCompletionPct    >= @TargetEmergencyGreen    THEN 'Green'
                WHEN EmergencyCompletionPct    >= @TargetEmergencyAmber    THEN 'Amber'
                ELSE 'Red'
              END AS EmergencyRAG

            , CASE
                WHEN NonEmergencyCompletionPct >= @TargetNonEmergencyGreen THEN 'Green'
                WHEN NonEmergencyCompletionPct >= @TargetNonEmergencyAmber THEN 'Amber'
                ELSE 'Red'
              END AS NonEmergencyRAG

            , CASE
                WHEN RightFirstTimePct         >= @TargetRFTGreen          THEN 'Green'
                WHEN RightFirstTimePct         >= @TargetRFTAmber          THEN 'Amber'
                ELSE 'Red'
              END AS RightFirstTimeRAG

            -- Expose thresholds so any consumer of this output can see
            -- exactly what targets were applied at report time
            , @TargetEmergencyGreen    AS TargetEmergencyGreen
            , @TargetEmergencyAmber    AS TargetEmergencyAmber
            , @TargetNonEmergencyGreen AS TargetNonEmergencyGreen
            , @TargetNonEmergencyAmber AS TargetNonEmergencyAmber
            , @TargetRFTGreen          AS TargetRFTGreen
            , @TargetRFTAmber          AS TargetRFTAmber
            , GETDATE()                AS ReportTimestamp

        FROM #ContractorMetrics
        ORDER BY ContractorName;

        DROP TABLE IF EXISTS #ContractorMetrics;

    END TRY

    BEGIN CATCH

        -- Surface meaningful error detail upstream to calling applications,
        -- BI tools and support engineers
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