# Rotherham Housing Repairs | BI Portfolio Project

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
- Audit-ready design & output: self-documenting, timestamped result sets
- Awaab's Law compliance framing within a BI reporting context
- "Built to outlast us" design philosophy -- no hardcoded assumptions,
  parameterised targets, dynamic date logic

---

## Technical Stack

| Layer | Technology |
|---|---|
| Database | SQL Server 2022 (LocalDB) |
| Query & Proc Development | SSMS |
| Data Generation | PowerBI, Python 3.13 - Faker, Pandas, SQLAlchemy, pyodbc |
| Visualisation | Python - Plotly |
| Version Control | GitHub |

---

## Status

| Component | Status |
|---|---|
| Database schema and reference data | Complete |
| Synthetic data generation | Complete |
| sp_GetContractorPerformance | Complete |
| sp_GetRepairsByCategory | Complete |
| vw_RepairJobs_Detail | Complete |
| vw_KPI_Summary | Complete |
| vw_PropertyStats | Complete |
| Dynamic reporting calendar | Complete |
| Plotly visualisation layer | Planned |
| GitHub publication | ongoing |

---

## Author

Martin Sefelin
[LinkedIn](http://www.linkedin.com/in/martinsefelin) |
[GitHub](https://github.com/)

*Developed with AI assistance (Claude, Anthropic) as part of an active 
public sector BI portfolio -- May 2026*

---
