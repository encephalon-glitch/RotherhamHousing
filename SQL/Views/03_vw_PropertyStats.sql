USE RotherhamHousingRepairs
GO
-- ============================================================
-- VIEW 3: Top level property state summary
-- “pivoted” on EPC rating for dashboards
-- ============================================================
CREATE OR ALTER VIEW dbo.vw_PropertyStats
AS
SELECT
      wg.WD24CD
    , wg.WD24NM
    , p.PropertyType
    , p.IsDecent
    , SUM(CASE WHEN p.EPC_Rating = 'A' THEN 1 ELSE 0 END) AS EPCR_A
    , SUM(CASE WHEN p.EPC_Rating = 'B' THEN 1 ELSE 0 END) AS EPCR_B
    , SUM(CASE WHEN p.EPC_Rating = 'C' THEN 1 ELSE 0 END) AS EPCR_C
    , SUM(CASE WHEN p.EPC_Rating = 'D' THEN 1 ELSE 0 END) AS EPCR_D
    , SUM(CASE WHEN p.EPC_Rating = 'E' THEN 1 ELSE 0 END) AS EPCR_E
    , SUM(CASE WHEN p.EPC_Rating = 'F' THEN 1 ELSE 0 END) AS EPCR_F
    , SUM(CASE WHEN p.EPC_Rating = 'G' THEN 1 ELSE 0 END) AS EPCR_G
    , COUNT(*)                                             AS TotalProperties
FROM dbo.Properties p
    INNER JOIN dbo.WardGeometry wg
        ON p.WardID = wg.WardID
GROUP BY
      wg.WD24CD
    , wg.WD24NM
    , p.PropertyType
    , p.IsDecent;
GO