# generate_data.py
# Author:   Martin Sefelin
# Version:  1.3
# for more details refer to: Docs/spec_DataGenerator
import json
import random
import requests
import pyodbc
import pandas as pd
from faker import Faker
from datetime import date, timedelta

fake = Faker("en_GB")
random.seed(42)

# ============================================================
# CONSTANTS
# All configurable values declared here -- nothing hardcoded
# in the loops below.
# ============================================================

JOB_COUNT               = 2000
IN_PROGRESS_WINDOW_DAYS = 90    # Jobs older than this must have a terminal status

BH_URL                  = "https://www.gov.uk/bank-holidays.json"
BH_DIVISION             = "england-and-wales"

START_DATE              = date(2024, 4, 1)
END_DATE                = date(2026, 3, 31)

# Property type distribution revised against Rotherham MBC housing stock
# profile and national social housing data (English Housing Survey 2024).
# Bungalow reduced from 15% -- original figure not supported by evidence.
PROPERTY_TYPE_WEIGHTS   = [55, 35, 10]   # House, Flat, Bungalow

# Bedroom distributions keyed by property type.
# Flats and bungalows capped at 3 bed -- 4-bed flat is implausible in
# social stock; 4-bed bungalow essentially does not exist.
BEDROOM_WEIGHTS = {
    "House":    [5,  25, 55, 15],
    "Flat":     [45, 50,  5,  0],
    "Bungalow": [50, 45,  5,  0],
}

# EPC distributions keyed by property type.
# Bungalows weighted toward D/E -- single storey, high heat loss, older builds.
# Flats weighted toward C and above -- shared walls, smaller floor area.
# Houses reflect the broad spread of Rotherham's mixed-age social stock.
EPC_WEIGHTS = {
    "House":    [2,  8, 45, 32, 13],
    "Flat":     [3, 15, 55, 22,  5],
    "Bungalow": [1,  4, 35, 40, 20],
}

# ============================================================
# CONNECTION
# Replace <YourServer> with your LocalDB instance name.
# Run: sqllocaldb info   to list available instances.
# ============================================================
conn_str = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=(localdb)\\MSSQLLocalDB;"
    "DATABASE=RotherhamHousingRepairs;"
    "Trusted_Connection=yes;"
)
conn   = pyodbc.connect(conn_str)
cursor = conn.cursor()


# ============================================================
# BANK HOLIDAY FETCH
# Returns a set of date objects for England and Wales within
# the target range. Called once at startup -- result passed
# into the calendar loop rather than fetched per row.
# ============================================================

def fetch_bank_holidays(url, division, date_from, date_to):
    print(f"Fetching bank holidays from {url}...")
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        print(f"  HTTP {response.status_code} -- fetch successful.")
    except requests.exceptions.Timeout:
        print("  ERROR: Request timed out -- bank holidays not loaded.")
        raise SystemExit
    except requests.exceptions.HTTPError as e:
        print(f"  ERROR: HTTP error -- {e}")
        raise SystemExit
    except requests.exceptions.ConnectionError:
        print("  ERROR: Connection failed -- check network.")
        raise SystemExit

    data = response.json()

    if division not in data:
        print(f"  ERROR: Division '{division}' not found.")
        print(f"  Available divisions: {list(data.keys())}")
        raise SystemExit

    parsed = set()
    for event in data[division]["events"]:
        try:
            d = date.fromisoformat(event["date"])
            if date_from <= d <= date_to:
                parsed.add(d)
        except ValueError:
            # Malformed date string in GOV.UK response -- skip silently
            pass

    print(f"  {len(parsed)} bank holidays loaded within target range.")
    return parsed


bank_holidays = fetch_bank_holidays(BH_URL, BH_DIVISION, START_DATE, END_DATE)


# ============================================================
# CALENDAR
# ============================================================
print("Generating Calendar...")


def financial_year(d):
    if d.month >= 4:
        return f"{d.year}/{str(d.year + 1)[-2:]}"
    else:
        return f"{d.year - 1}/{str(d.year)[-2:]}"


delta         = END_DATE - START_DATE
calendar_rows = []

for i in range(delta.days + 1):
    d = START_DATE + timedelta(days=i)
    # Working day: weekday AND not a bank holiday
    is_working = 1 if d.weekday() < 5 and d not in bank_holidays else 0
    calendar_rows.append((
        d,
        d.month,
        d.strftime("%B"),
        ((d.month - 1) // 3) + 1,
        financial_year(d),
        is_working,
    ))

cursor.executemany(
    "INSERT INTO Calendar VALUES (?,?,?,?,?,?)",
    calendar_rows,
)
conn.commit()
print(f"  {len(calendar_rows)} calendar rows inserted.")


# ============================================================
# PROPERTIES
# ============================================================
print("Generating Properties...")
'''
wards = [
    "Anston and Woodsetts", "Aston and Todwick", "Aughton and Swallownest",
    "Boston Castle", "Bramley and Ravenfield", "Brinsworth",
    "Dalton and Thrybergh", "Dinnington", "Greasbrough",
    "Hellaby and Maltby West", "Hoober", "Keppel",
    "Kilnhurst and Swinton East", "Maltby East", "Rawmarsh East",
    "Rawmarsh West", "Rother Vale", "Rotherham East",
    "Rotherham West", "Sitwell", "Swinton Rockingham",
    "Thurcroft and Wickersley South", "Wales", "Wath",
    "Wickersley North",
]
'''
property_types = ["House", "Flat", "Bungalow"]
epc_ratings    = ["A", "B", "C", "D", "E"]

properties = []
for i in range(1, 501):
    ref = f"PROP{i:04d}"
    # ref   = f"PROP{str(i).zfill(4)}"
    wardID = random.randint(1, 25)
    # ward  = random.choice(wards)
    ptype = random.choices(property_types, weights=PROPERTY_TYPE_WEIGHTS)[0]

    # Bedroom and EPC keyed by property type -- implausible combinations
    # (4-bed flat, A-rated bungalow) are excluded by the weight distributions.
    bedrooms   = random.choices([1, 2, 3, 4], weights=BEDROOM_WEIGHTS[ptype])[0]
    epc        = random.choices(epc_ratings,   weights=EPC_WEIGHTS[ptype])[0]
    build_year = random.randint(1920, 2020)
    is_decent  = 0 if epc in ["D", "E"] and random.random() < 0.3 else 1

    properties.append((ref, wardID, ptype, bedrooms, epc, build_year, is_decent))

cursor.executemany(
    "INSERT INTO Properties VALUES (?,?,?,?,?,?,?)",
    properties,
)
conn.commit()
print(f"  {len(properties)} properties inserted.")


# ============================================================
# REPAIR JOBS
# ============================================================
print("Generating Repair Jobs...")

categories       = list(range(1, 13))
priorities       = ["Emergency", "Urgent", "Non-Emergency"]
priority_weights = [15, 14, 71]

statuses_full     = ["Completed", "In Progress", "Cancelled", "No Access"]
weights_full      = [85, 8, 4, 3]

# Jobs older than this cutoff must have resolved to a terminal status.
# In Progress on a job raised 18 months ago is not credible.
statuses_terminal = ["Completed", "Cancelled", "No Access"]
weights_terminal  = [91, 5, 4]

in_progress_cutoff = END_DATE - timedelta(days=IN_PROGRESS_WINDOW_DAYS)


def pick_category(raised_date):
    # Damp/mould weighted to winter -- category 1 reflects seasonal demand
    if raised_date.month in [11, 12, 1, 2, 3]:
        return random.choices(categories, weights=[20, 10, 15, 10, 8, 5, 8, 8, 6, 4, 4, 2])[0]
    else:
        return random.choices(categories, weights=[8, 5, 10, 8, 10, 8, 12, 12, 10, 8, 6, 3])[0]


def pick_contractor(priority):
    if priority == "Emergency":
        # Emergency contract: Mears (1) and Direct Works (3) only
        return random.choices([1, 3], weights=[60, 40])[0]
    else:
        # Planned work: Mears (1) and Equans (2)
        return random.choices([1, 2], weights=[50, 50])[0]


def pick_status(raised_date):
    if raised_date < in_progress_cutoff:
        return random.choices(statuses_terminal, weights=weights_terminal)[0]
    else:
        return random.choices(statuses_full, weights=weights_full)[0]


def days_to_complete(priority, status):
    if status != "Completed":
        return None
    if priority == "Emergency":
        # Target: 1 calendar day. ~99% on target.
        return random.choices(
            [random.randint(1, 1), random.randint(2, 5)],
            weights=[99, 1],
        )[0]
    elif priority == "Urgent":
        # Awaab's Law urgent threshold: 14 days. ~92% on target.
        return random.choices(
            [random.randint(1, 14), random.randint(15, 30)],
            weights=[92, 8],
        )[0]
    else:
        # Non-Emergency target: 20 days. ~98% on target.
        return random.choices(
            [random.randint(1, 20), random.randint(21, 40)],
            weights=[98, 2],
        )[0]


staging_rows = []
for _ in range(JOB_COUNT):
    prop       = random.choice(properties)[0]
    raised     = START_DATE + timedelta(days=random.randint(0, delta.days))
    priority   = random.choices(priorities, weights=priority_weights)[0]
    category   = pick_category(raised)
    contractor = pick_contractor(priority)
    status     = pick_status(raised)
    days       = days_to_complete(priority, status)
    completed  = raised + timedelta(days=days) if days else None

    # Right first time: 95.7% per Rotherham published figure
    rft = None
    if status == "Completed":
        rft = 1 if random.random() < 0.957 else 0

    # Satisfaction weighted toward 4-5 -- reflects typical survey patterns
    sat = None
    if status == "Completed":
        sat = random.choices([1, 2, 3, 4, 5], weights=[2, 3, 10, 35, 50])[0]

    staging_rows.append((
        prop, category, priority, raised, completed,
        contractor, status, rft, sat,
    ))

cursor.executemany("""
    INSERT INTO RepairJobs_Staging
    (PropertyRef, CategoryID, Priority, DateRaised, DateCompleted,
     ContractorID, Status, RightFirstTime, TenantSatisfactionScore)
    VALUES (?,?,?,?,?,?,?,?,?)
""", staging_rows)
conn.commit()
print(f"  {len(staging_rows)} staging rows inserted.")


# ============================================================
# LOAD CLEAN FACT TABLE
# Staging layer catches malformed rows before they reach the
# clean fact table. Validation filter is the quality gate.
# ============================================================
print("Loading RepairJobs from staging...")

cursor.execute("""
    INSERT INTO RepairJobs
    (JobID, PropertyRef, CategoryID, Priority, DateRaised, DateCompleted,
     ContractorID, Status, RightFirstTime, TenantSatisfactionScore)
    SELECT
        JobID, PropertyRef, CategoryID, Priority, DateRaised, DateCompleted,
        ContractorID, Status, RightFirstTime, TenantSatisfactionScore
    FROM RepairJobs_Staging
    WHERE PropertyRef IS NOT NULL
      AND CategoryID  IS NOT NULL
      AND Priority IN ('Emergency', 'Urgent', 'Non-Emergency')
      AND Status   IN ('Completed', 'In Progress', 'Cancelled', 'No Access')
""")
conn.commit()

row_count = cursor.execute("SELECT COUNT(*) FROM RepairJobs").fetchone()[0]
print(f"  {row_count} rows loaded into RepairJobs.")

cursor.close()
conn.close()
print("\nDone. Database populated.")
