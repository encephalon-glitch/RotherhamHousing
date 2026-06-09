let
// ============================================================
// Reporting Calendar | v2.7
// Author:   Martin Sefelin
// Purpose:  Dynamic date dimension for Power BI.
//           Seeds from today, spans YearsBack/YearsForward.
//           Fetches bank holidays live from GOV.UK. Falls back
//           to weekday-only working day calculation on any
//           failure. Table always renders. BankHolidayStatus
//           on every row explains current state.
//           Fully portable | adapts to any geography via
//           config block alone. Zero magic values in logic.
// ============================================================
// Changes:  v2.7____Added explicit datatype assignment.
//           v2.6____FiscalYearStartMonth in config. All fiscal
//                    derivations parameterised. FiscalYearStartMonth
//                    passed explicitly into fnDate | no closures
//                    anywhere. Stub variables documented for
//                    bank holiday removal. Fully international.
//           v2.5____Fully adaptive division discovery via
//                    BHSearchTerm. Ambiguity guard. Four
//                    distinct failure modes.
//           v2.4____Single HasError check. BHDivisionNames
//                    and EventsAndDates inside success branch.
//           v2.3____ParsedJSON assigned once. BHDivisionNames
//                    as two-column transparency table.
//           v2.2____Stages 2-3 collapsed. Record.FieldValues
//                    replaces hardcoded division key.
//                    Config block updated.
//           v2.1____Three-stage error handling. Calendar
//                    always loads.
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

    // Case-insensitive search term used to discover the correct
    // division in the GOV.UK response. Change to "scotland" or
    // "northern-ireland" for other UK geographies, or replace
    // the fetch block entirely for non-GOV.UK sources.
    // To disable bank holiday fetching, remove section 3 and replace with:
    //   BankHolidaySet    = {},
    //   BankHolidayStatus = "Bank holidays not configured",
    
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
// 3. BANK HOLIDAYS | adaptive fetch with four failure modes
//
//    Every failure path returns:
//      [ BHSet = {}, Status = "<plain-English message>" ]
//    Table always renders. IsWorkingDay degrades to
//    weekday-only. BankHolidayStatus explains what happened.
//
//    Stage 1:  GOV.UK unreachable
//    Stage 2a: no division matching BHSearchTerm found
//    Stage 2b: multiple divisions match BHSearchTerm
//    Stage 2c: division found, events structure broken
// ============================================================

    // One HTTP call, one parse | both referenced downstream.
    RawFetch   = try Web.Contents(GovUK),
    ParsedJSON = if RawFetch[HasError] then null else
                     Json.Document(RawFetch[Value]),

    BankHolidayResult =
        if RawFetch[HasError] then
            [
                BHSet  = {},
                Status = "Bank holiday data unavailable: GOV.UK could not be "
                         & "reached. Working day calculations use weekdays only. "
                         & "Retry or check Power BI gateway and privacy settings."
            ]
        else
            let
                // FieldNames called once | used by discovery,
                // ambiguity guard, and BHDivisionNames.
                FieldNames = Record.FieldNames(ParsedJSON),

                // Discovers all divisions whose name contains BHSearchTerm.
                // Case-insensitive so casing changes in source do not break it.
                EnglandMatches = List.Select(
                    FieldNames,
                    each Text.Contains(Text.Lower(_), Text.Lower(BHSearchTerm))
                ),

                // Transparency table | always visible in step inspector
                // on successful fetch. Shows every division GOV.UK returned
                // alongside its current index for reference.
                BHDivisionNames = Table.FromRecords(
                    List.TransformMany(
                        {0 .. List.Count(FieldNames) - 1},
                        each {_},
                        (i, _) => [
                            Index        = i,
                            DivisionName = FieldNames{i}
                        ]
                    )
                ),

                // Resolved only when exactly one match found.
                EnglandKey = List.First(EnglandMatches),

                // Navigate by discovered key name | no positional index.
                // Single try | full chain works or it does not.
                EventsAndDates = try List.Transform(
                    Record.Field(ParsedJSON, EnglandKey)[events],
                    each Date.From([date])
                )
            in
                if List.Count(EnglandMatches) = 0 then
                    [
                        BHSet  = {},
                        Status = "Bank holiday data unavailable: no division "
                                 & "matching '"
                                 & BHSearchTerm
                                 & "' found in GOV.UK response. "
                                 & "Working day calculations use weekdays only. "
                                 & "Divisions found: "
                                 & Text.Combine(FieldNames, ", ")
                                 & ". Update BHSearchTerm in the config block."
                    ]
                else if List.Count(EnglandMatches) > 1 then
                    [
                        BHSet  = {},
                        Status = "Bank holiday data unavailable: '"
                                 & BHSearchTerm
                                 & "' matched multiple divisions | "
                                 & Text.Combine(EnglandMatches, ", ")
                                 & ". Working day calculations use weekdays only. "
                                 & "Tighten BHSearchTerm in the config block "
                                 & "to match exactly one division."
                    ]
                else if EventsAndDates[HasError] then
                    [
                        BHSet  = {},
                        Status = "Bank holiday data unavailable: division '"
                                 & EnglandKey
                                 & "' was found but its event records no longer "
                                 & "contain a date field. Working day calculations "
                                 & "use weekdays only. The M-code source query "
                                 & "requires revision."
                    ]
                else
                    [
                        BHSet  = EventsAndDates[Value],
                        Status = "OK"
                    ],

    // Unpack | consumed by row function only.
    BankHolidaySet    = BankHolidayResult[BHSet],
    BankHolidayStatus = BankHolidayResult[Status],

// ============================================================
// 4. ROW FUNCTION
//    All parameters passed explicitly |no closure on outer
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

        // ___Calendar fields___
        CalendarYear    = Date.Year(d),
        MonthNumber     = Date.Month(d),
        MonthName       = Date.MonthName(d),
        MonthShort      = Text.Start(MonthName, 3),
        YearMonth       = Date.ToText(d, "yyyy-MM"),
        CalendarQuarter = "Q" & Text.From(Date.QuarterOfYear(d)),
        DayOfWeekNum    = Date.DayOfWeek(d, Day.Monday) + 1,   // Mon=1, Sun=7
        DayName         = Date.DayOfWeekName(d),

        // ___Fiscal year (fully derived from fiscalStart)___
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

        // ___Relative offsets (to seed date)___
        RelativeDay     = Duration.Days(d - seed),
        RelativeMonth   = (CalendarYear * 12 + MonthNumber)
                          - (Date.Year(seed) * 12 + Date.Month(seed)),
        RelativeQuarter = Number.IntegerDivide(RelativeMonth, 3),
        RelativeYear    = CalendarYear - Date.Year(seed),

        // ___Convenience flags___
        IsCurrentMonth      = RelativeMonth = 0,

        // Derives seed fiscal year using the same logic as FiscalYear
        // so IsCurrentFiscalYear is consistent across all geographies.
        IsCurrentFiscalYear = FiscalYear =
                                  (if Date.Month(seed) >= fiscalStart
                                   then Date.Year(seed)
                                   else Date.Year(seed) - 1),

        IsLast12Months = RelativeMonth >= -11 and RelativeMonth <= 0,

        // ___Working day logic___
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