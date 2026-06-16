USE [RotherhamHousingRepairs]
GO

/****** Object:  UserDefinedFunction [dbo].[fn_WorkingDaysBetween]    Script Date: 16/06/2026 09:55:08 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER   FUNCTION [dbo].[fn_WorkingDaysBetween]
(
      @StartDate DATE
    , @EndDate   DATE
)
RETURNS INT
AS
BEGIN

    -- NULL in, NULL out -- consistent with SP NULL discipline throughout
    IF @StartDate IS NULL OR @EndDate IS NULL
        RETURN NULL;

    -- Negative range is not a data error but the result is zero not negative
    IF @StartDate >= @EndDate
        RETURN 0;

    RETURN (
        SELECT COUNT(*)
        FROM dbo.Calendar
        WHERE CalendarDate >  @StartDate  -- exclusive start: day of raise is not a working day elapsed
          AND CalendarDate <= @EndDate    -- inclusive end: completion day counts
          AND IsWorkingDay = 1
    );

END;
GO


