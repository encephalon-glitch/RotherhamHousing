USE RotherhamHousingRepairs
GO
-- ============================================================
-- VIEW 3: Top level property state summary
-- “pivoted” on EPC rating for dashboards
-- ============================================================
CREATE VIEW dbo.vw_PropertyStats
AS
SELECT
    Ward,
    PropertyType,
    IsDecent,
    SUM(CASE WHEN EPC_Rating = 'A' THEN 1 ELSE 0 END) AS EPCR_A,
    SUM(CASE WHEN EPC_Rating = 'B' THEN 1 ELSE 0 END) AS EPCR_B,
    SUM(CASE WHEN EPC_Rating = 'C' THEN 1 ELSE 0 END) AS EPCR_C,
    SUM(CASE WHEN EPC_Rating = 'D' THEN 1 ELSE 0 END) AS EPCR_D,
    SUM(CASE WHEN EPC_Rating = 'E' THEN 1 ELSE 0 END) AS EPCR_E,
    SUM(CASE WHEN EPC_Rating = 'F' THEN 1 ELSE 0 END) AS EPCR_F,
    SUM(CASE WHEN EPC_Rating = 'G' THEN 1 ELSE 0 END) AS EPCR_G,
    COUNT(*) AS TotalProperties
FROM [RotherhamHousingRepairs].[dbo].[Properties]
GROUP BY
    Ward
    , PropertyType
    , IsDecent
GO