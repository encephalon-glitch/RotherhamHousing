USE RotherhamHousingRepairs;
GO
-- Ward Geometry
INSERT INTO dbo.WardGeometry (WD24CD, WD24NM, WDLat, WDLon) VALUES
('E05012993', 'Anston & Woodsetts', 53.33933, -1.19348),
('E05012994', 'Aston & Todwick', 53.36291, -1.2825),
('E05012995', 'Aughton & Swallownest', 53.3722, -1.3267),
('E05012996', 'Boston Castle', 53.42185, -1.35651),
('E05012997', 'Bramley & Ravenfield', 53.456, -1.26726),
('E05012998', 'Brinsworth', 53.40444, -1.36695),
('E05012999', 'Dalton & Thrybergh', 53.44509, -1.30132),
('E05013000', 'Dinnington', 53.3867, -1.18642),
('E05013001', 'Greasbrough', 53.45132, -1.37454),
('E05013002', 'Hellaby & Maltby West', 53.4226, -1.22454),
('E05013003', 'Hoober', 53.48278, -1.40146),
('E05013004', 'Keppel', 53.4494, -1.4144),
('E05013005', 'Kilnhurst & Swinton East', 53.47773, -1.30816),
('E05013006', 'Maltby East', 53.41431, -1.17193),
('E05013007', 'Rawmarsh East', 53.45971, -1.3247),
('E05013008', 'Rawmarsh West', 53.46583, -1.35396),
('E05013009', 'Rother Vale', 53.38505, -1.35643),
('E05013010', 'Rotherham East', 53.43856, -1.33694),
('E05013011', 'Rotherham West', 53.43148, -1.39306),
('E05013012', 'Sitwell', 53.40454, -1.30576),
('E05013013', 'Swinton Rockingham', 53.48504, -1.32685),
('E05013014', 'Thurcroft & Wickersley South', 53.39659, -1.2502),
('E05013015', 'Wales', 53.32969, -1.28252),
('E05013016', 'Wath', 53.49909, -1.33856),
('E05013017', 'Wickersley North', 53.43053, -1.28824);

GO

-- Contractors
INSERT INTO Contractors (ContractorName, ContractType) VALUES
('Mears', 'Both'),
('Equans', 'Planned'),
('Direct Works', 'Emergency');
GO

-- Repair Categories
INSERT INTO RepairCategories (CategoryName, CategoryGroup) VALUES
('Damp and Mould', 'Damp/Mould'),
('Condensation', 'Damp/Mould'),
('Boiler Repair', 'Heating'),
('Heating System', 'Heating'),
('Electrical Fault', 'Electrical'),
('Smoke Alarm', 'Electrical'),
('Roof Repair', 'Structural'),
('Window Repair', 'Structural'),
('Plumbing Leak', 'Plumbing'),
('Blocked Drain', 'Plumbing'),
('Door Repair', 'General'),
('Flooring', 'General');
GO