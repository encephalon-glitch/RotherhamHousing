USE RotherhamHousingRepairs;
GO

/*
=======================================================================
Procedure:  dbo.GetContractorPerformance
Author:     Martin Sefelin
Version:    1.6
Changed:    2026-06-15

Purpose:
    Returns contractor performance metrics across the selected period,
    including:
        - Emergency completion performance
        - Non-emergency completion performance
        - Right First Time (RFT)
        - Tenant satisfaction
        - Damp & mould workload
        - RAG status indicators

Notes:
    - Defaults to 2024/25 financial year if no dates supplied.
    - KPI targets are parameterised for easier policy changes.
    - fn_WorkingDaysBetween returns NULL if either date is NULL,
      consistent with NULL discipline throughout -- non-completed
      jobs fall out of the completion numerator correctly.
    - RAG returns NULL where a contractor operates in a single
      priority band and the metric does not apply (e.g. Direct Works
      has no Non-Emergency jobs; Equans has no Emergency jobs).
      NULL means not applicable -- not a data error.
=======================================================================
*/

CREATE OR ALTER PROCEDURE dbo.GetContractorPerformance
(
      @ContractorName              VARCHAR(100) = NULL
    , @DateFrom                    DATE         = NULL
    , @DateTo                      DATE         = NULL

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

        IF @DateFrom IS NULL
            SET @DateFrom = '2024-04-01';

        IF @DateTo IS NULL
            SET @DateTo = '2025-03-31';

        IF @DateFrom > @DateTo
            THROW 50001, 'DateFrom cannot be later than DateTo.', 1;

        DROP TABLE IF EXISTS #ContractorMetrics;

        SELECT

              c.ContractorName

            , @DateFrom AS PeriodFrom
            , @DateTo   AS PeriodTo

            , COUNT(r.JobID)                                        AS TotalJobs

            , SUM(IIF(r.Priority = 'Emergency',     1, 0))          AS EmergencyJobs
            , SUM(IIF(r.Priority = 'Non-Emergency', 1, 0))          AS NonEmergencyJobs

            /*
            Emergency: 1 calendar day -- legal definition, not working days.
            */
            , ROUND(
                100.0
                * SUM(CASE
                        WHEN r.Priority = 'Emergency'
                         AND r.Status   = 'Completed'
                         AND r.DaysToComplete <= 1
                        THEN 1 ELSE 0
                      END)
                / NULLIF(SUM(IIF(r.Priority = 'Emergency', 1, 0)), 0)
              , 1)                                                   AS EmergencyCompletionPct

            /*
            Non-Emergency: 20 working days per housing repairs convention.
            Function called on source dates -- DaysToComplete is calendar days
            and would silently overstate compliance against a working-day target.
            NULL DateCompleted returns NULL from the function, correctly
            excluding incomplete jobs from the numerator without a separate guard.
            */
            , ROUND(
                100.0
                * SUM(CASE
                        WHEN r.Priority = 'Non-Emergency'
                         AND r.Status   = 'Completed'
                         AND dbo.fn_WorkingDaysBetween(r.DateRaised, r.DateCompleted) <= 20
                        THEN 1 ELSE 0
                      END)
                / NULLIF(SUM(IIF(r.Priority = 'Non-Emergency', 1, 0)), 0)
              , 1)                                                   AS NonEmergencyCompletionPct

            , ROUND(
                100.0
                * SUM(IIF(r.RightFirstTime = 1, 1, 0))
                / NULLIF(SUM(IIF(r.RightFirstTime IS NOT NULL, 1, 0)), 0)
              , 1)                                                   AS RightFirstTimePct

            , ROUND(
                AVG(CAST(r.TenantSatisfactionScore AS FLOAT))
              , 2)                                                   AS AvgSatisfaction

            , SUM(IIF(rc.CategoryGroup = 'Damp/Mould', 1, 0))       AS DampMouldJobs

        INTO #ContractorMetrics

        FROM dbo.RepairJobs r
            INNER JOIN dbo.Contractors     c  ON r.ContractorID = c.ContractorID
            INNER JOIN dbo.RepairCategories rc ON r.CategoryID  = rc.CategoryID

        WHERE
            (@ContractorName IS NULL OR c.ContractorName = @ContractorName)
            AND r.DateRaised BETWEEN @DateFrom AND @DateTo

        GROUP BY
            c.ContractorName;


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

            /*
            NULL branch first -- a contractor with no jobs in a priority band
            returns NULL from NULLIF, not a performance failure.
            */
            , CASE
                WHEN EmergencyCompletionPct IS NULL                  THEN NULL
                WHEN EmergencyCompletionPct >= @TargetEmergencyGreen THEN 'Green'
                WHEN EmergencyCompletionPct >= @TargetEmergencyAmber THEN 'Amber'
                ELSE 'Red'
              END AS EmergencyRAG

            , CASE
                WHEN NonEmergencyCompletionPct IS NULL                     THEN NULL
                WHEN NonEmergencyCompletionPct >= @TargetNonEmergencyGreen THEN 'Green'
                WHEN NonEmergencyCompletionPct >= @TargetNonEmergencyAmber THEN 'Amber'
                ELSE 'Red'
              END AS NonEmergencyRAG

            , CASE
                WHEN RightFirstTimePct >= @TargetRFTGreen THEN 'Green'
                WHEN RightFirstTimePct >= @TargetRFTAmber THEN 'Amber'
                ELSE 'Red'
              END AS RightFirstTimeRAG

            -- Expose thresholds so BI exports are self-documenting
            , @TargetEmergencyGreen    AS TargetEmergencyGreen
            , @TargetEmergencyAmber    AS TargetEmergencyAmber
            , @TargetNonEmergencyGreen AS TargetNonEmergencyGreen
            , @TargetNonEmergencyAmber AS TargetNonEmergencyAmber
            , @TargetRFTGreen          AS TargetRFTGreen
            , @TargetRFTAmber          AS TargetRFTAmber

        FROM #ContractorMetrics
        ORDER BY ContractorName;

        DROP TABLE IF EXISTS #ContractorMetrics;

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
