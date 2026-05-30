USE RotherhamHousingRepairs;
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