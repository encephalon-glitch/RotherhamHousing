let

// ============================================================
// Reporting Calendar | v3.1
// Author:      Martin Sefelin
// PURPOSE:     Dynamic date dimension with resilient GOV.UK
//              bank holiday integration. Falls back to
//              weekday-only working-day logic if holiday
//              data is unavailable. Table always renders.
//              BankHolidayStatus on every row explains state.
// ============================================================
// 1. CONFIGURATION
// ============================================================

SeedDate             = Date.From(DateTime.LocalNow()),
YearsBack            = 2,
YearsForward         = 1,

// Fiscal year start month. UK = 4 (Apr), US = 10 (Oct),
// Australia = 7 (Jul), calendar year = 1 (Jan).
FiscalYearStartMonth = 4,

GovUK                = "https://www.gov.uk/bank-holidays.json",

// england | scotland | northern-ireland
BHSearchTerm         = "england",

// ============================================================
// 2. DATE RANGE
// ============================================================

StartDate = Date.StartOfYear(Date.AddYears(SeedDate, -YearsBack)),
EndDate   = Date.EndOfYear(Date.AddYears(SeedDate, YearsForward)),

DateList  = List.Dates(
    StartDate,
    Duration.Days(EndDate - StartDate) + 1,
    #duration(1, 0, 0, 0)
),

// ============================================================
// 3. BANK HOLIDAYS | resilient GOV.UK fetch
//
// Class 1: Connection errors
//   - URL, network, SSL or permission failures.
//
// Class 2: Data errors
//   - Invalid JSON.
//   - No matching division.
//   - Ambiguous division match.
//   - Unexpected events/date structure.
//
// Any failure returns:
//   [ BHSet = {}, Status = "<message>" ]
//
// The table still loads and working-day calculations
// fall back to weekday-only logic.
// ============================================================
// Class 1: Connection / URL / Permission errors
// ============================================================

RawFetch =
    // Binary.Buffer forces eager evaluation so network/URL failures
    // are caught by try rather than deferred by lazy evaluation.
    try Binary.Buffer(Web.Contents(GovUK)),

BankHolidayResult =
    if RawFetch[HasError] then
        [
            BHSet = {},
            Status =
                "Bank holiday data unavailable: "
                // RawFetch[Error][Message] surfaces GOV.UK's own error
                // string including URL and HTTP code where available.
                & (try RawFetch[Error][Message]
                   otherwise "Connection, URL or permission error")
                & ". Working day calculations use weekdays only."
        ]

// ============================================================
// Class 2: Document / Schema errors
// ============================================================

    else
        let
            RawContent = RawFetch[Value],

            // Wrapped in try -- a 404 HTML page or malformed response
            // fails here rather than propagating garbage downstream.
            ParsedJSON =
                try Json.Document(RawContent)
        in
            if ParsedJSON[HasError] then
                [
                    BHSet = {},
                    Status =
                        "Bank holiday data unavailable: GOV.UK response "
                        & "could not be parsed as JSON. Working day "
                        & "calculations use weekdays only."
                ]
            else
                let
                    JsonData = ParsedJSON[Value],

                    FieldNames =
                        Record.FieldNames(JsonData),

                    // Case-insensitive search avoids hardcoding the division
                    // key -- survives GOV.UK renaming or reordering divisions.
                    EnglandMatches =
                        List.Select(
                            FieldNames,
                            each Text.Contains(
                                Text.Lower(_),
                                Text.Lower(BHSearchTerm)
                            )
                        )
                in
                    if List.Count(EnglandMatches) = 0 then
                        [
                            BHSet = {},
                            Status =
                                "Bank holiday data unavailable: no division matching '"
                                & BHSearchTerm
                                & "' found. Divisions available: "
                                & Text.Combine(FieldNames, ", ")
                        ]

                    else if List.Count(EnglandMatches) > 1 then
                        [
                            BHSet = {},
                            Status =
                                "Bank holiday data unavailable: '"
                                & BHSearchTerm
                                & "' matched multiple divisions: "
                                & Text.Combine(EnglandMatches, ", ")
                        ]

                    else
                        let
                            EnglandKey =
                                EnglandMatches{0},

                            // Single try -- full navigation chain works or it does not.
                            EventsAndDates =
                                try
                                    List.Transform(
                                        Record.Field(
                                            JsonData,
                                            EnglandKey
                                        )[events],
                                        each Date.From([date])
                                    )
                        in
                            if EventsAndDates[HasError] then
                                [
                                    BHSet = {},
                                    Status =
                                        "Bank holiday data unavailable: division '"
                                        & EnglandKey
                                        & "' no longer contains the expected "
                                        & "events/date structure."
                                ]
                            else
                                [
                                    BHSet = EventsAndDates[Value],
                                    Status = "OK"
                                ],

BankHolidaySet    = BankHolidayResult[BHSet],
BankHolidayStatus = BankHolidayResult[Status],

// ============================================================
// 4. ROW FUNCTION
//    All parameters passed explicitly -- no closure on outer
//    variables anywhere in this query.
// ============================================================

fnDate = (
    d           as date,
    seed        as date,
    bhSet       as list,
    bhStatus    as text,
    fiscalStart as number
) as record =>
let

    // --- Calendar fields ---
    CalendarYear    = Date.Year(d),
    MonthNumber     = Date.Month(d),
    MonthName       = Date.MonthName(d),
    MonthShort      = Text.Start(MonthName, 3),
    YearMonth       = Date.ToText(d, "yyyy-MM"),
    CalendarQuarter = "Q" & Text.From(Date.QuarterOfYear(d)),
    DayOfWeekNum    = Date.DayOfWeek(d, Day.Monday) + 1,   // Mon=1, Sun=7
    DayName         = Date.DayOfWeekName(d),

    // --- Fiscal year (fully derived from fiscalStart) ---
    FiscalYear = if MonthNumber >= fiscalStart
                 then CalendarYear
                 else CalendarYear - 1,

    // FiscalMonth 1 always = fiscalStart month regardless of geography.
    FiscalMonth = if MonthNumber >= fiscalStart
                  then MonthNumber - fiscalStart + 1
                  else MonthNumber + (12 - fiscalStart + 1),

    FiscalQuarter   = "Q" & Text.From(Number.RoundUp(FiscalMonth / 3)),

    FiscalYearLabel = Text.From(FiscalYear)
                      & "/"
                      & Text.End(Text.From(FiscalYear + 1), 2),

    // --- Relative offsets (to seed date) ---
    RelativeDay     = Duration.Days(d - seed),
    RelativeMonth   = (CalendarYear * 12 + MonthNumber)
                      - (Date.Year(seed) * 12 + Date.Month(seed)),
    RelativeQuarter = Number.IntegerDivide(RelativeMonth, 3),
    RelativeYear    = CalendarYear - Date.Year(seed),

    // --- Convenience flags ---
    IsCurrentMonth      = RelativeMonth = 0,

    // Derives seed fiscal year using the same logic as FiscalYear
    // so IsCurrentFiscalYear is consistent across all geographies.
    IsCurrentFiscalYear = FiscalYear =
                              (if Date.Month(seed) >= fiscalStart
                               then Date.Year(seed)
                               else Date.Year(seed) - 1),

    IsLast12Months = RelativeMonth >= -11 and RelativeMonth <= 0,

    // --- Working day logic ---
    // Three separate steps so each is independently visible
    // in the Power Query step inspector when debugging SLA counts.
    IsWeekend     = DayOfWeekNum >= 6,
    IsBankHoliday = List.Contains(bhSet, d),   // false for all if bhSet = {}
    IsWorkingDay  = not IsWeekend and not IsBankHoliday

in
    [
        Date                = d,

        CalendarYear        = CalendarYear,
        MonthNumber         = MonthNumber,
        MonthName           = MonthName,
        MonthShort          = MonthShort,
        YearMonth           = YearMonth,
        CalendarQuarter     = CalendarQuarter,
        DayOfWeek           = DayOfWeekNum,
        DayName             = DayName,

        FiscalYear          = FiscalYear,
        FiscalYearLabel     = FiscalYearLabel,
        FiscalMonth         = FiscalMonth,
        FiscalQuarter       = FiscalQuarter,

        RelativeDay         = RelativeDay,
        RelativeMonth       = RelativeMonth,
        RelativeQuarter     = RelativeQuarter,
        RelativeYear        = RelativeYear,

        IsCurrentMonth      = IsCurrentMonth,
        IsCurrentFiscalYear = IsCurrentFiscalYear,
        IsLast12Months      = IsLast12Months,

        IsBankHoliday       = IsBankHoliday,
        IsWorkingDay        = IsWorkingDay,
        BankHolidayStatus   = bhStatus
    ],

// ============================================================
// 5. MATERIALISE
// ============================================================

TableOut = Table.TransformColumnTypes(
    // generate table
    Table.FromRecords(
        List.Transform(
            DateList,
            each fnDate(_, SeedDate, BankHolidaySet, BankHolidayStatus, FiscalYearStartMonth)
        )
    ),
    // output schema | prevents silent inference at refresh
    {
        {"Date",                type date},
        {"CalendarYear",        Int64.Type},
        {"MonthNumber",         Int64.Type},
        {"MonthName",           type text},
        {"MonthShort",          type text},
        {"YearMonth",           type text},
        {"CalendarQuarter",     type text},
        {"DayOfWeek",           Int64.Type},
        {"DayName",             type text},
        {"FiscalYear",          Int64.Type},
        {"FiscalYearLabel",     type text},
        {"FiscalMonth",         Int64.Type},
        {"FiscalQuarter",       type text},
        {"RelativeDay",         Int64.Type},
        {"RelativeMonth",       Int64.Type},
        {"RelativeQuarter",     Int64.Type},
        {"RelativeYear",        Int64.Type},
        {"IsCurrentMonth",      type logical},
        {"IsCurrentFiscalYear", type logical},
        {"IsLast12Months",      type logical},
        {"IsBankHoliday",       type logical},
        {"IsWorkingDay",        type logical},
        {"BankHolidayStatus",   type text}
    }
)

in
    TableOut