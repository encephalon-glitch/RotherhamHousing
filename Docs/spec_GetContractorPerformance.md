# Procedure Spec: dbo.GetContractorPerformance

## Important Disclaimer

This specification relates to a portfolio project built entirely on
synthetic data. It is not affiliated with or representative of Rotherham
Metropolitan Borough Council or any real operational system. See
`DISCLAIMER.md` at the project root for full details.

---

## Purpose

Track and report contractor performance across key housing repairs KPIs
for Rotherham Council's Housing Repairs service. Designed to support
contract management, budget planning, RSH audit readiness and Awaab's
Law compliance monitoring.

---

## Audience

- BI team -- procedure is the data source for dashboard and visualisation
  layers
- Housing Repairs managers -- quarterly contract review meetings
- Finance -- annual budget projections and contractor cost performance
- RSH inspection readiness -- audit-ready, timestamped, self-documenting
  output

---

## Reporting Modes

| Mode | Parameter Value | Date Range | Primary Use |
|---|---|---|---|
| Last Fiscal Year | `LAST_FISCAL_YEAR` | 1 Apr (n-1) to 31 Mar (n) | Annual review, budget projections |
| Last Quarter | `LAST_QUARTER` | Previous complete quarter | Contract management meetings |
| Last Two Quarters | `LAST_TWO_QUARTERS` | Previous two complete quarters | Trend comparison |
| Fiscal Year to Date | `FYTD` | 1 Apr (current) to today | Live operational view |

**Default Mode:** `LAST_FISCAL_YEAR`

---

## Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `@ContractorName` | VARCHAR(100) | NULL | NULL returns all contractors |
| `@ReportingMode` | VARCHAR(20) | `LAST_FISCAL_YEAR` | Drives date window logic |
| `@DateFrom` | DATE | NULL | Manual override -- bypasses mode logic |
| `@DateTo` | DATE | NULL | Manual override -- bypasses mode logic |
| `@TargetEmergencyGreen` | DECIMAL(5,1) | 98.0 | Parameterised for policy changes |
| `@TargetEmergencyAmber` | DECIMAL(5,1) | 95.0 | |
| `@TargetNonEmergencyGreen` | DECIMAL(5,1) | 94.0 | |
| `@TargetNonEmergencyAmber` | DECIMAL(5,1) | 90.0 | |
| `@TargetRFTGreen` | DECIMAL(5,1) | 93.0 | |
| `@TargetRFTAmber` | DECIMAL(5,1) | 90.0 | |

---

## KPIs Covered

| KPI | Target | RAG Logic |
|---|---|---|
| Emergency completion % | 98% within 1 working day | Green / Amber / Red |
| Non-emergency completion % | 94% within 20 working days | Green / Amber / Red |
| Right First Time % | 93% | Green / Amber / Red |
| Tenant satisfaction | Average score | No RAG -- informational |
| Damp and mould jobs | Volume count | Awaab's Law compliance flag |

---

## Output Columns

- Contractor name, reporting period, mode label
- Volume metrics -- total jobs, emergency, non-emergency
- KPI percentages
- RAG status per KPI
- KPI thresholds used -- self-documenting for audit purposes
- Report timestamp

---

## Design Principles

- `@ReportingMode` drives date logic -- no hardcoded dates in production
- Manual `@DateFrom` and `@DateTo` overrides bypass mode logic entirely
  for ad-hoc analysis
- KPI targets are parameterised -- policy changes require no code changes
- Temp table staging separates calculation from RAG evaluation
- Output is self-documenting -- thresholds and timestamp included in
  every result set
- `NULLIF` guards against division by zero where a contractor has no
  jobs in a category
- Error handling returns meaningful messages upstream to BI tools and
  calling applications
- Built to support RSH inspection readiness -- audit trail baked in
  by design

---

## Example Calls

```sql
-- Default: last full fiscal year, all contractors
EXEC dbo.GetContractorPerformance;

-- Mears only, last fiscal year
EXEC dbo.GetContractorPerformance
    @ContractorName = 'Mears';

-- All contractors, last quarter
EXEC dbo.GetContractorPerformance
    @ReportingMode = 'LAST_QUARTER';

-- Custom date range override
EXEC dbo.GetContractorPerformance
    @DateFrom = '2025-10-01',
    @DateTo   = '2025-12-31';

-- Tightened KPI targets
EXEC dbo.GetContractorPerformance
      @ReportingMode           = 'LAST_FISCAL_YEAR'
    , @TargetEmergencyGreen    = 99.0
    , @TargetNonEmergencyGreen = 96.0
    , @TargetRFTGreen          = 95.0;
```

---

## Versioning

| Version | Status | Notes |
|---|---|---|
| v1.0 | Complete | Prototype -- single SELECT, hardcoded RAG thresholds |
| v1.1 | Complete | Temp table staging, parameterised targets |
| v1.2 | Complete | CREATE OR ALTER, input validation, error handling |
| v1.3 | Complete | IIF consolidation, dynamic dates, timestamp |
| v1.4 | In development | ReportingMode parameter, quarter logic |