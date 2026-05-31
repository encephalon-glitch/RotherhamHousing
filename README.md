# Rotherham Housing Repairs — BI Portfolio Project

## Important Disclaimer

This is an independent portfolio project built entirely on synthetic,
randomly generated data.

It is not affiliated with, commissioned by, or representative of Rotherham
Metropolitan Borough Council, its systems, contractors, or operational data.
All figures, performance metrics, property references, repair jobs, and KPI
results are fabricated for demonstration purposes only.

Contractor names (Mears, Equans) and KPI targets are referenced solely
because they appear in Rotherham's publicly available Housing Strategy
2025-30. Their inclusion does not imply any actual performance data,
endorsement, or relationship with this project.

---

## Project Overview

A portfolio piece demonstrating end-to-end BI development skills applied
to a realistic public sector housing repairs scenario.

The project simulates the kind of reporting infrastructure a council BI
team might build to monitor contractor performance, track Awaab's Law
compliance, and support RSH inspection readiness -- built from scratch
across SQL, Python, and data visualisation layers.

---

## Why This Scenario?

Rotherham Council's Housing Strategy 2025-30 is publicly available and
provides a credible, realistic context for this work:

- Active RSH inspection expected during the strategy period
- Awaab's Law now in force -- damp and mould response times are a legal
  compliance obligation
- Named contractors (Mears, Equans) operating across housing repairs
- Published KPI targets providing realistic performance benchmarks

Building against a real strategic context -- even with synthetic data --
produces more meaningful and transferable portfolio work than a generic
fictional scenario.

---

## What This Project Demonstrates

- End-to-end pipeline design from data generation through to reporting layer
- SQL Server stored procedure development with production-grade patterns
- Synthetic data generation in Python using Faker, Pandas and SQLAlchemy
- RAG status reporting with parameterised KPI thresholds
- Audit-ready output design -- self-documenting, timestamped result sets
- Awaab's Law compliance framing within a BI reporting context
- "Built to outlast us" design philosophy -- no hardcoded assumptions,
  parameterised targets, dynamic date logic

---

## Technical Stack

| Layer | Technology |
|---|---|
| Database | SQL Server 2022 (LocalDB) |
| Query & Proc Development | SSMS |
| Data Generation | Python 3.13 -- Faker, Pandas, SQLAlchemy, pyodbc |
| Visualisation | Python -- Plotly |
| Version Control | GitHub |

---

## Stored Procedure: GetContractorPerformance

Full specification in `Docs/spec_GetContractorPerformance.md`

Full schema reference in `Docs/schema.md`

### Reporting Modes

> Reporting modes were evaluated and descoped in v1.4. The existing 
> `@DateFrom` and `@DateTo` parameters provide equivalent flexibility 
> without additional complexity. May be revisited in future iterations 
> if a BI tool integration requires named mode parameters.

Defaults to last complete fiscal year to align with the synthetic dataset.
In production against a live dataset, the intended default is last complete
calendar month.

| Mode | Parameter Value | Date Range | Primary Use |
|---|---|---|---|
| Last Fiscal Year | `LAST_FISCAL_YEAR` | 1 Apr (n-1) to 31 Mar (n) | Annual review, budget projections |
| Last Quarter | `LAST_QUARTER` | Previous complete quarter | Contract management meetings |
| Last Two Quarters | `LAST_TWO_QUARTERS` | Previous two complete quarters | Trend comparison |
| Fiscal Year to Date | `FYTD` | 1 Apr (current) to today | Live operational view |

### Example Calls

```sql
-- Default: last full fiscal year, all contractors
EXEC dbo.GetContractorPerformance;

-- Mears only, last fiscal year
EXEC dbo.GetContractorPerformance
    @ContractorName = 'Mears';

-- Custom date range override
EXEC dbo.GetContractorPerformance
    @DateFrom = '2025-10-01',
    @DateTo   = '2025-12-31';

-- Tightened KPI targets
EXEC dbo.GetContractorPerformance
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
| v1.4 | Complete | Reporting period updated, descoped reporting modes, inline comments added |

---

## Status

| Component | Status |
|---|---|
| Database schema and reference data | Complete |
| Synthetic data generation | Complete |
| Views | Complete |
| GetContractorPerformance v1.3 | Complete |
| GetContractorPerformance v1.4 | Complete |
| GetRepairsByCategory procedure | in development |
| Plotly visualisation layer | Planned |
| GitHub publication | Complete |

---

## Author

Martin Sefelin
[LinkedIn](http://www.linkedin.com/in/martinsefelin) |
[GitHub](https://github.com/)

*Developed with AI assistance (Claude, Anthropic) as part of an active 
public sector BI portfolio -- May 2026*