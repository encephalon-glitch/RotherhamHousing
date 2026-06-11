# Spec: Reporting Calendar
See `PowerBI/ReportingCalendarPBI_Mcode.pq`

---

| Version | Summary |
|---|---|
| v3.1 | Fetch block refactored into two explicit defensive classes. Class 1 catches all connection/URL/permission failures via `try` + `Binary.Buffer`. Class 2 catches all document/schema failures via `try Json.Document` and division navigation. `ManualStatusHandling` removed -- unreliable outside custom connector context. Confirmed working across all tested failure scenarios. |
| v3.0 | `Binary.Buffer` wraps `Web.Contents` inside `try`, forcing eager evaluation. DNS/network failures now caught at `RawFetch[HasError]`. Error message surfaced via `try RawFetch[Error][Message] otherwise` fallback. Two-layer fetch architecture confirmed by testing. |
| v2.9 | `Response.Status?` operator trialled. Reverted -- DNS failures throw before `Value.Metadata` evaluates due to M-code lazy evaluation. |
| v2.8 | `ManualStatusHandling` added to `Web.Contents`. HTTP 404/500/503 intercepted and surfaced with status code in message. |
| v2.7 | `Table.TransformColumnTypes` applied at materialise step. All 22 output columns explicitly typed. Schema locked at refresh. |
| v2.6 | `FiscalYearStartMonth` added to config. All fiscal derivations parameterised. `fiscalStart` passed explicitly into `fnDate` -- zero closures. |
| v2.5 | `BHSearchTerm` replaces positional index. Adaptive division discovery via `List.Select`. Ambiguity guard added. Five distinct failure modes. |
| v2.4 | `RawFetch[HasError]` checked exactly once. `BHDivisionNames` and `EventsAndDates` moved inside success branch. |
| v2.3 | `ParsedJSON` assigned once. `BHDivisionNames` added as two-column transparency table for step inspector. |
| v2.2 | Hardcoded division key removed. `Record.FieldValues` navigates JSON dynamically. Config block introduced. |
| v2.1 | Three-stage error handling introduced. Calendar always loads regardless of fetch outcome. |

---

## Purpose

Dynamic date dimension for Power BI. Designed for housing repairs reporting
environments where working day accuracy directly affects SLA and regulatory
compliance calculations including Awaab's Law thresholds.

---

## Architecture
The query is structured in five sections:
1. **Configuration** -- all tuneable values in one place, no magic values in logic
2. **Date range** -- derived from config, generates `DateList`
3. **Bank holiday fetch** -- two defensive classes, five failure modes. See `PowerBI/ReportingCalendarPBI_Mcode.pq` -- Section 3.
4. **Row function `fnDate`** -- all parameters passed explicitly, no closures
5. **Materialise** -- typed output, schema locked at refresh

---

## Configuration Block

All geographic and fiscal assumptions are surfaced here. No values elsewhere
in the query need changing to adapt for a different environment.

| Variable | Default | Notes |
|---|---|---|
| `SeedDate` | `DateTime.LocalNow()` | Rolling seed, never goes stale |
| `YearsBack` | `2` | Configurable range |
| `YearsForward` | `1` | Configurable range |
| `FiscalYearStartMonth` | `4` | UK Apr-Mar. US=10, AU=7, calendar=1 |
| `GovUK` | GOV.UK JSON endpoint | Replace for non-GOV.UK sources |
| `BHSearchTerm` | `"england"` | Case-insensitive division search term |

---

## Bank Holiday Fetch

### Design Decision -- Adaptive Discovery

The query does not hardcode the GOV.UK division key `"england-and-wales"` or
rely on a positional index. Instead it searches division names dynamically
using `BHSearchTerm`. This means the query survives GOV.UK renaming or
reordering divisions without requiring a code change.

`BHSearchTerm` in config is the single point of change for geography.

### Transparency Step

`BHDivisionNames` is a two-column table (Index, DivisionName) built from the
live API response. Visible in the Power Query step inspector -- confirms what
GOV.UK is currently returning and what `BHSearchTerm` resolves to without
needing to inspect the raw response.

### Failure Modes

All five failure paths return `BHSet = {}` and a plain-English `BankHolidayStatus`
message. The calendar always loads. `IsWorkingDay` degrades to weekday-only.
Nothing fails silently.

| Class | Trigger | Message directs maintainer to |
|---|---|---|
| Class 1 | Connection, URL, SSL or permission failure | Surfaces GOV.UK's own error string including HTTP code where available |
| Class 2a | GOV.UK response cannot be parsed as JSON | Check GovUK URL in config block |
| Class 2b | No division matches `BHSearchTerm` | Lists actual divisions returned, update `BHSearchTerm` |
| Class 2c | Multiple divisions match `BHSearchTerm` | Lists ambiguous matches, tighten `BHSearchTerm` |
| Class 2d | Division found, events structure broken | M-code revision required |

---

## Row Function -- `fnDate`

All outer scope variables passed explicitly as parameters. No closures anywhere
in the query. Parameters:

| Parameter | Type | Purpose |
|---|---|---|
| `d` | date | Date being processed |
| `seed` | date | Relative offset base |
| `bhSet` | list | Bank holiday dates, `{}` on failure |
| `bhStatus` | text | Bank holiday status message |
| `fiscalStart` | number | Fiscal year start month from config |

### Fiscal Year Derivation

All fiscal fields derive from `fiscalStart` parameter -- no hardcoded month
assumptions. `FiscalMonth = 1` always corresponds to `fiscalStart` month
regardless of geography.

### Working Day Logic

Three explicit steps retained for step inspector visibility:

```
IsWeekend     = DayOfWeekNum >= 6
IsBankHoliday = List.Contains(bhSet, d)
IsWorkingDay  = not IsWeekend and not IsBankHoliday
```

`IsBankHoliday` retained as independent output column for audit and debugging.

---

## Output Schema

22 columns explicitly typed via `Table.TransformColumnTypes` at materialise
step. Locks schema at refresh -- prevents silent type inference errors in the
Power BI model.

| Column | Type | Notes |
|---|---|---|
| `Date` | date | Primary key for model relationships |
| `CalendarYear` | Int64 | |
| `MonthNumber` | Int64 | |
| `MonthName` | text | Locale-aware via Power BI environment |
| `MonthShort` | text | First 3 characters of MonthName |
| `YearMonth` | text | yyyy-MM format |
| `CalendarQuarter` | text | Q1-Q4 |
| `DayOfWeek` | Int64 | Mon=1, Sun=7 (ISO) |
| `DayName` | text | Locale-aware via Power BI environment |
| `FiscalYear` | Int64 | Start year of fiscal period |
| `FiscalYearLabel` | text | e.g. 2025/26 |
| `FiscalMonth` | Int64 | 1-12 from fiscal year start |
| `FiscalQuarter` | text | Q1-Q4 fiscal |
| `RelativeDay` | Int64 | Signed offset from seed date |
| `RelativeMonth` | Int64 | Signed offset from seed month |
| `RelativeQuarter` | Int64 | Signed offset from seed quarter |
| `RelativeYear` | Int64 | Signed offset from seed year |
| `IsCurrentMonth` | logical | |
| `IsCurrentFiscalYear` | logical | |
| `IsLast12Months` | logical | Rolling 12 month window |
| `IsBankHoliday` | logical | false for all if fetch failed |
| `IsWorkingDay` | logical | false on weekends and bank holidays |
| `BankHolidayStatus` | text | "OK" or plain-English failure message |

---

## Locale

`MonthName` and `DayName` are locale-aware -- they return values in the
language of the Power BI environment. No logic in the query depends on
their string values so this is safe across all locales.

---

## Removing Bank Holiday Fetch

To disable bank holiday fetching entirely, remove section 3 and replace with:

```m
BankHolidaySet    = {},
BankHolidayStatus = "Bank holidays not configured",
```

`fnDate` and the materialise step require no changes.
