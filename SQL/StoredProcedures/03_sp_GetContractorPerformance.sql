USE RotherhamHousingRepairs;
GO

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
            SET @DateFrom = DATEFROMPARTS(
                                CASE WHEN MONTH(GETDATE()) >= 4
                                     THEN YEAR(GETDATE())
                                     ELSE YEAR(GETDATE()) - 1 END,
                                4, 1);

        IF @DateTo IS NULL
			SET @DateTo = DATEFROMPARTS(
							  CASE WHEN MONTH(GETDATE()) >= 4
								   THEN YEAR(GETDATE())
								   ELSE YEAR(GETDATE()) - 1 END,
							  3, 31);

        IF @DateFrom > @DateTo
            THROW 50001, 'DateFrom cannot be later than DateTo.', 1;

        DROP TABLE IF EXISTS #ContractorMetrics;

        SELECT
              c.ContractorName
            , @DateFrom AS PeriodFrom
            , @DateTo   AS PeriodTo
            , COUNT(r.JobID) AS TotalJobs
            , SUM(IIF(r.Priority = 'Emergency',     1, 0)) AS EmergencyJobs
            , SUM(IIF(r.Priority = 'Non-Emergency', 1, 0)) AS NonEmergencyJobs

            , ROUND(
                100.0 * SUM(CASE WHEN r.Priority = 'Emergency'
                                  AND r.Status = 'Completed'
                                  AND r.DaysToComplete <= 1 THEN 1 ELSE 0 END)
                / NULLIF(SUM(IIF(r.Priority = 'Emergency', 1, 0)), 0)
              , 1) AS EmergencyCompletionPct

            , ROUND(
                100.0 * SUM(CASE WHEN r.Priority = 'Non-Emergency'
                                  AND r.Status = 'Completed'
                                  AND r.DaysToComplete <= 20 THEN 1 ELSE 0 END)
                / NULLIF(SUM(IIF(r.Priority = 'Non-Emergency', 1, 0)), 0)
              , 1) AS NonEmergencyCompletionPct

            , ROUND(
                100.0 * SUM(IIF(r.RightFirstTime = 1,        1, 0))
                / NULLIF(SUM(IIF(r.RightFirstTime IS NOT NULL, 1, 0)), 0)
              , 1) AS RightFirstTimePct

            , ROUND(AVG(CAST(r.TenantSatisfactionScore AS FLOAT)), 2) AS AvgSatisfaction

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

            , @TargetEmergencyGreen    AS TargetEmergencyGreen
            , @TargetEmergencyAmber    AS TargetEmergencyAmber
            , @TargetNonEmergencyGreen AS TargetNonEmergencyGreen
            , @TargetNonEmergencyAmber AS TargetNonEmergencyAmber
            , @TargetRFTGreen          AS TargetRFTGreen
            , @TargetRFTAmber          AS TargetRFTAmber
            , GETDATE()                AS ReportTimeStamp

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