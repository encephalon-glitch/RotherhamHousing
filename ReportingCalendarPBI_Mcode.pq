let

// ============================================================
// Reporting Calendar | v2.1
// Author:   Martin Sefelin
// Purpose:  Dynamic date dimension for Power BI.
//           Config.: SeedDate, YearsBack, YearsForward, GovUK
//			 SeedDate can accomodate different reporting needs
//           Fetches England & Wales bank holidays live from
//           GOV.UK. Falls back to weekday-only working day
//           calculation if the API is unavailable or has
//           changed structure, with a plain-English status
//           message on every row explaining what failed.
// Changes:  v2.1 -- Three-stage error handling on bank
//                    holiday fetch: network failure,
//                    structure change, and schema drift
//                    each produce a distinct BankHolidayStatus
//                    message. Calendar always loads.
// ============================================================
// 1. CONFIGURATION
// ============================================================

    SeedDate     	= Date.From(DateTime.LocalNow()),
    YearsBack    	= 2,
    YearsForward 	= 1,
	GovUK 			= "https://www.gov.uk/bank-holidays.json",

    StartDate = Date.StartOfYear(Date.AddYears(SeedDate, -YearsBack)),
    EndDate   = Date.EndOfYear(Date.AddYears(SeedDate, YearsForward)),

    DateList = List.Dates(
        StartDate,
        Duration.Days(EndDate - StartDate) + 1,
        #duration(1, 0, 0, 0)
    ),

// ============================================================
// 2. BANK HOLIDAYS | three-stage defensive fetch
// ============================================================
//    Stage 1: network/HTTP failure
//      GOV.UK unreachable, timeout, or gateway/privacy issue.
//      Fix: retry later or check Power BI data source settings.
//
//    Stage 2: structure change
//      API responded but "england-and-wales" or "events" key
//      is missing. GOV.UK has restructured their JSON.
//      Fix: the M-code source query requires revision.
//
//    Stage 3: schema drift
//      "events" exists but records no longer carry a "date"
//      field, or the list is empty. Silent drift caught here
//      before it produces rubbish in IsWorkingDay.
//      Fix: the M-code source query requires revision.
//
//    All failure paths return the same shape:
//      [ BHSet = {}, Status = "<plain-English message>" ]
//    so the row function is identical regardless of outcome.
// ============================================================

    // Stage 1. Attempt the HTTP fetch
    RawFetch = try Web.Contents(GovUK),

    BankHolidayResult =
        if RawFetch[HasError] then
            [
                BHSet  = {},
                Status = "Bank holiday data unavailable: GOV.UK could not be "
                         & "reached. Working day calculations use weekdays only. "
                         & "Retry or check Power BI gateway and privacy settings."
            ]
        else

            // Stage 2. Attempt JSON navigation to england-and-wales events
            let
                ParseAttempt = try
                    Json.Document(RawFetch[Value])[#"england-and-wales"][events]
            in
                if ParseAttempt[HasError] then
                    [
                        BHSet  = {},
                        Status = "Bank holiday data unavailable: GOV.UK response "
                                 & "structure has changed. Working day calculations "
                                 & "use weekdays only. The M-code source query "
                                 & "requires revision."
                    ]
                else

                    // Stage 3. Validate the events list has usable date fields
                    let
                        Events     = ParseAttempt[Value],
                        FirstEvent = try Events{0}[date]
                    in
                        if not Value.Is(Events, type list)
                           or List.IsEmpty(Events)
                           or FirstEvent[HasError] then
                            [
                                BHSet  = {},
                                Status = "Bank holiday data unavailable: GOV.UK "
                                         & "event records no longer contain a date "
                                         & "field or the list is empty. Working day "
                                         & "calculations use weekdays only. The "
                                         & "M-code source query requires revision."
                            ]
                        else
                            [
                                BHSet  = List.Transform(Events, each Date.From([date])),
                                Status = "OK"
                            ],

    // Unpack result | used by row function
    BankHolidaySet    = BankHolidayResult[BHSet],
    BankHolidayStatus = BankHolidayResult[Status],

// ============================================================
// 3. ROW FUNCTION
// ============================================================
//    Seed, bank holiday set, and status passed explicitly | 
//    no closure on outer variables.
// ============================================================

    fxDate = (d as date, seed as date, bhSet as list, bhStatus as text) as record =>
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

        // --- Fiscal year (UK Apr-Mar) ---
        FiscalYear = if MonthNumber >= 4
                     then CalendarYear
                     else CalendarYear - 1,

        FiscalMonth = if MonthNumber >= 4
                      then MonthNumber - 3
                      else MonthNumber + 9,

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
        IsCurrentFiscalYear = FiscalYear =
                                  (if Date.Month(seed) >= 4
                                   then Date.Year(seed)
                                   else Date.Year(seed) - 1),
        IsLast12Months      = RelativeMonth >= -11 and RelativeMonth <= 0,

        // --- Working day logic ---
        // Kept in three separate steps so each is independently
        // testable and visible in the Power Query step inspector.
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
// 4. MATERIALISE
// ============================================================

    TableOut = Table.FromRecords(
        List.Transform(
            DateList,
            each fxDate(_, SeedDate, BankHolidaySet, BankHolidayStatus)
        )
    )

in
    TableOut
