USE RotherhamHousingRepairs;
GO

-- Ward_Geometry dimension
CREATE TABLE WardGeometry (
    WardID INT IDENTITY(1,1) PRIMARY KEY,
    WD24CD VARCHAR(20) NOT NULL UNIQUE,
    WD24NM VARCHAR(100) NOT NULL,
    WDLat DECIMAL(9,6) NULL,
    WDLon DECIMAL(9,6) NULL
);
GO
-- Contractors dimension
CREATE TABLE Contractors (
    ContractorID    INT IDENTITY(1,1) PRIMARY KEY,
    ContractorName  VARCHAR(100) NOT NULL,
    ContractType    VARCHAR(20) NOT NULL
);
GO

-- Repair categories dimension
CREATE TABLE RepairCategories (
    CategoryID      INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName    VARCHAR(100) NOT NULL,
    CategoryGroup   VARCHAR(50) NOT NULL
);
GO

-- Properties dimension
CREATE TABLE Properties (
    PropertyRef     VARCHAR(10) PRIMARY KEY,
    WardID          INT NOT NULL REFERENCES WardGeometry(WardID),
    PropertyType    VARCHAR(20) NOT NULL,
    BedroomCount    INT NOT NULL,
    EPC_Rating      CHAR(1) NOT NULL,
    BuildYear       INT NOT NULL,
    IsDecent        BIT NOT NULL DEFAULT 1
);
GO

-- Calendar dimension
CREATE TABLE Calendar (
    CalendarDate    DATE PRIMARY KEY,
    MonthNum        INT NOT NULL,
    MonthName       VARCHAR(20) NOT NULL,
    Quarter         INT NOT NULL,
    FinancialYear   VARCHAR(10) NOT NULL,
    IsWorkingDay    BIT NOT NULL DEFAULT 1
);
GO

-- Repair jobs staging table
CREATE TABLE RepairJobs_Staging (
    JobID                   INT IDENTITY(1,1) PRIMARY KEY,
    PropertyRef             VARCHAR(10) NOT NULL,
    CategoryID              INT NOT NULL,
    Priority                VARCHAR(15) NOT NULL,
    DateRaised              DATE NOT NULL,
    DateCompleted           DATE NULL,
    ContractorID            INT NOT NULL,
    Status                  VARCHAR(20) NOT NULL,
    RightFirstTime          BIT NULL,
    TenantSatisfactionScore INT NULL
);
GO

-- Repair jobs clean fact table
CREATE TABLE RepairJobs (
    JobID                   INT PRIMARY KEY,
    PropertyRef             VARCHAR(10) NOT NULL REFERENCES Properties(PropertyRef),
    CategoryID              INT NOT NULL REFERENCES RepairCategories(CategoryID),
    Priority                VARCHAR(15) NOT NULL,
    DateRaised              DATE NOT NULL,
    DateCompleted           DATE NULL,
    ContractorID            INT NOT NULL REFERENCES Contractors(ContractorID),
    Status                  VARCHAR(20) NOT NULL,
    RightFirstTime          BIT NULL,
    TenantSatisfactionScore INT NULL,
    DaysToComplete          AS DATEDIFF(DAY, DateRaised, DateCompleted)
);
GO