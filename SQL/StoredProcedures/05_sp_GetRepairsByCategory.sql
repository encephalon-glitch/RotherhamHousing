USE RotherhamHousingRepairs;
GO

/*
=======================================================================
Procedure:  dbo.GetRepairsByCategory
Author:     Martin Sefelin
Version:    1.3
Changed:    2026-06-16

Purpose:
    Returns repair volume and compliance metrics by category,
    including Awaab's Law three-band RAG across Emergency,
    Urgent and Non-Emergency priorities.

Change log:
    v1.0    Initial build.
    v1.1    Three-band RAG (Emergency/Urgent/Non-Emergency),
            #CategoryMetrics and #RepeatDampProperties staging tables,
            priority-aware NULL discipline. Committed.
    v1.2    Non-Emergency SLA evaluation flipped from calendar days
            to working days via dbo.fn_WorkingDaysBetween, consistent
            with GetContractorPerformance v1.5.
            Emergency and Urgent remain as calendar days -- legislative
            definitions.
    v1.3    CancelledJobs added to staging SELECT and final output,
            alongside existing NoAccessCount. Both are volume signals
            only -- no RAG applied. Surfaces job lifecycle transparency
            for audit and RSH review without distorting compliance KPIs.
            NULL RAG branch moved to first position in all three RAG
            CASE blocks for consistency with GetContractorPerformance v1.6.

Notes:
    - Defaults to 2024/25 financial year if no dates supplied.
    - fn_WorkingDaysBetween returns NULL for NULL DateCompleted,
      so incomplete jobs fall out of the compliance numerator without
      an additional guard.
    - CancelledJobs and NoAccessCount are volume signals only.
      Job-level audit detail (cancellation reason, access attempt
      history) sits in the RepairJobs fact table, not this procedure.
=======================================================================
*/

CREATE OR ALTER PROCEDURE dbo.GetRepairsByCategory
(
      @CategoryID                  INT          = NULL
    , @DateFrom                    DATE         = NULL
    , @DateTo                      DATE         = NULL

    -- Awaab's Law thresholds (calendar days for Emergency and Urgent,
    -- working days for Non-Emergency)
    , @TargetEmergencyDays         INT          = 1
    , @TargetUrgentDays            INT          = 14
    , @TargetNonEmergencyDays      INT          = 20

    -- RAG thresholds
    , @TargetComplianceGreen       DECIMAL(5,1) = 95.0
    , @TargetComplianceAmber       DECIMAL(5,1) = 90.0

    -- Repeat damp threshold: flag properties with this many or more
    -- damp/mould jobs in the period
    , @RepeatDampThreshold         INT          = 2
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

        /*
        Stage category-level metrics before RAG evaluation.
        Separating calculation from CASE logic keeps both layers readable
        and avoids repeating expensive aggregates.
        */
        DROP TABLE IF EXISTS #CategoryMetrics;

        SELECT

              rc.CategoryID
            , rc.CategoryName
            , rc.CategoryGroup

            , @DateFrom AS PeriodFrom
            , @DateTo   AS PeriodTo

            , COUNT(r.JobID)                                        AS TotalJobs

            , SUM(IIF(r.Priority = 'Emergency',     1, 0))          AS EmergencyJobs
            , SUM(IIF(r.Priority = 'Urgent',        1, 0))          AS UrgentJobs
            , SUM(IIF(r.Priority = 'Non-Emergency', 1, 0))          AS NonEmergencyJobs

            /*
            Emergency compliance: 1 calendar day (Awaab's Law / legal).
            */
            , ROUND(
                100.0
                * SUM(CASE
                        WHEN r.Priority = 'Emergency'
                         AND r.Status   = 'Completed'
                         AND r.DaysToComplete <= @TargetEmergencyDays
                        THEN 1 ELSE 0
                      END)
                / NULLIF(SUM(IIF(r.Priority = 'Emergency', 1, 0)), 0)
              , 1)                                                   AS EmergencyCompliancePct

            /*
            Urgent compliance: 14 calendar days (Awaab's Law / legal).
            */
            , ROUND(
                100.0
                * SUM(CASE
                        WHEN r.Priority = 'Urgent'
                         AND r.Status   = 'Completed'
                         AND r.DaysToComplete <= @TargetUrgentDays
                        THEN 1 ELSE 0
                      END)
                / NULLIF(SUM(IIF(r.Priority = 'Urgent', 1, 0)), 0)
              , 1)                                                   AS UrgentCompliancePct

            /*
            Non-Emergency compliance: 20 working days.
            Working-day count sourced from fn_WorkingDaysBetween rather than
            DaysToComplete (which is calendar days) to avoid systematic
            overcounting against a working-day target.
            */
            , ROUND(
                100.0
                * SUM(CASE
                        WHEN r.Priority = 'Non-Emergency'
                         AND r.Status   = 'Completed'
                         AND dbo.fn_WorkingDaysBetween(r.DateRaised, r.DateCompleted) <= @TargetNonEmergencyDays
                        THEN 1 ELSE 0
                      END)
                / NULLIF(SUM(IIF(r.Priority = 'Non-Emergency', 1, 0)), 0)
              , 1)                                                   AS NonEmergencyCompliancePct

            -- Volume signals: surface job lifecycle without distorting KPIs
            , SUM(IIF(r.Status = 'Cancelled', 1, 0))                AS CancelledJobs
            , SUM(IIF(r.Status = 'No Access', 1, 0))                AS NoAccessCount

        INTO #CategoryMetrics

        FROM dbo.RepairJobs      r
            INNER JOIN dbo.RepairCategories rc ON r.CategoryID = rc.CategoryID

        WHERE
            (@CategoryID IS NULL OR r.CategoryID = @CategoryID)
            AND r.DateRaised BETWEEN @DateFrom AND @DateTo

        GROUP BY
              rc.CategoryID
            , rc.CategoryName
            , rc.CategoryGroup;


        /*
        Identify properties with repeat damp/mould jobs above threshold.
        Stored separately so the count can surface in the output without
        complicating the main aggregation.
        */
        DROP TABLE IF EXISTS #RepeatDampProperties;

        SELECT
              r.PropertyRef
            , COUNT(r.JobID) AS DampJobCount
        INTO #RepeatDampProperties
        FROM dbo.RepairJobs      r
            INNER JOIN dbo.RepairCategories rc ON r.CategoryID = rc.CategoryID
        WHERE
            rc.CategoryGroup = 'Damp/Mould'
            AND r.DateRaised BETWEEN @DateFrom AND @DateTo
        GROUP BY
            r.PropertyRef
        HAVING
            COUNT(r.JobID) >= @RepeatDampThreshold;


        SELECT

              cm.CategoryID
            , cm.CategoryName
            , cm.CategoryGroup
            , cm.PeriodFrom
            , cm.PeriodTo
            , cm.TotalJobs
            , cm.EmergencyJobs
            , cm.UrgentJobs
            , cm.NonEmergencyJobs
            , cm.EmergencyCompliancePct
            , cm.UrgentCompliancePct
            , cm.NonEmergencyCompliancePct
            , cm.CancelledJobs
            , cm.NoAccessCount

            -- Repeat damp count only meaningful for the Damp/Mould group
            , CASE
                WHEN cm.CategoryGroup = 'Damp/Mould'
                THEN (SELECT COUNT(*) FROM #RepeatDampProperties)
                ELSE NULL
              END                                                    AS RepeatDampProperties

            /*
            NULL branch first -- consistent with GetContractorPerformance v1.6
            and with NULL discipline throughout. A category with no jobs in a
            priority band is not a compliance failure.
            */
            , CASE
                WHEN cm.EmergencyCompliancePct IS NULL                   THEN NULL
                WHEN cm.EmergencyCompliancePct >= @TargetComplianceGreen THEN 'Green'
                WHEN cm.EmergencyCompliancePct >= @TargetComplianceAmber THEN 'Amber'
                ELSE 'Red'
              END AS EmergencyRAG

            , CASE
                WHEN cm.UrgentCompliancePct IS NULL                   THEN NULL
                WHEN cm.UrgentCompliancePct >= @TargetComplianceGreen THEN 'Green'
                WHEN cm.UrgentCompliancePct >= @TargetComplianceAmber THEN 'Amber'
                ELSE 'Red'
              END AS UrgentRAG

            , CASE
                WHEN cm.NonEmergencyCompliancePct IS NULL                   THEN NULL
                WHEN cm.NonEmergencyCompliancePct >= @TargetComplianceGreen THEN 'Green'
                WHEN cm.NonEmergencyCompliancePct >= @TargetComplianceAmber THEN 'Amber'
                ELSE 'Red'
              END AS NonEmergencyRAG

            -- Expose thresholds so BI exports are self-documenting
            , @TargetEmergencyDays    AS TargetEmergencyDays
            , @TargetUrgentDays       AS TargetUrgentDays
            , @TargetNonEmergencyDays AS TargetNonEmergencyDays
            , @TargetComplianceGreen  AS TargetComplianceGreen
            , @TargetComplianceAmber  AS TargetComplianceAmber
            , @RepeatDampThreshold    AS RepeatDampThreshold

        FROM #CategoryMetrics cm
        ORDER BY cm.CategoryGroup, cm.CategoryName;

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
