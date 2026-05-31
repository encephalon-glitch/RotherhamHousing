import pyodbc
import pandas as pd
from faker import Faker
import random
from datetime import date, timedelta

# ============================================================
# generate_data_v1.1
#
# Changes from v1.0:
#   - Added 'Urgent' priority band (15% overall, weighted
#     higher for Damp/Mould jobs) to support three-tier
#     Awaab's Law RAG in GetRepairsByCategory procedure
#   - Added 'No Access' status (~5% overall, ~10% for
#     Damp/Mould jobs) to surface compliance exposure in
#     Awaab's Law reporting
#   - days_to_complete updated to handle Urgent band:
#     14-day target, ~96% compliance rate
#   - Staging load filter updated to include new values
#   - Contractor assignment unchanged -- already correctly
#     respects ContractType (Emergency/Planned/Both)
# ============================================================

fake = Faker('en_GB')
random.seed(42)

# ============================================================
# CONNECTION
# ============================================================
conn_str = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=(localdb)\\MSSQLLocalDB;"
    "DATABASE=RotherhamHousingRepairs;"
    "Trusted_Connection=yes;"
)
conn = pyodbc.connect(conn_str)
cursor = conn.cursor()

# ============================================================
# CALENDAR
# ============================================================
print("Generating Calendar...")

def financial_year(d):
    if d.month >= 4:
        return f"{d.year}/{str(d.year + 1)[-2:]}"
    else:
        return f"{d.year - 1}/{str(d.year)[-2:]}"

start_date = date(2025, 4, 1)
end_date = date(2026, 3, 31)
delta = end_date - start_date

calendar_rows = []
for i in range(delta.days + 1):
    d = start_date + timedelta(days=i)
    is_working = 1 if d.weekday() < 5 else 0
    calendar_rows.append((
        d,
        d.month,
        d.strftime('%B'),
        ((d.month - 1) // 3) + 1,
        financial_year(d),
        is_working
    ))

cursor.executemany(
    "INSERT INTO Calendar VALUES (?,?,?,?,?,?)",
    calendar_rows
)
conn.commit()
print(f"  {len(calendar_rows)} calendar rows inserted.")

# ============================================================
# PROPERTIES
# ============================================================
print("Generating Properties...")

wards = [
    'Rotherham Town Centre', 'Maltby', 'Rawmarsh East', 'Rawmarsh West',
    'Wath', 'Dinnington', 'Kiveton Park', 'Thurcroft', 'Wingfield',
    'Boston Castle', 'Hellaby', 'Sitwell', 'Hoober', 'Wickersley',
    'Anston and Woodsetts', 'Bramley and Ravenfield'
]
property_types = ['House', 'Flat', 'Bungalow']
epc_ratings = ['A', 'B', 'C', 'D', 'E']
epc_weights = [2, 8, 50, 30, 10]

properties = []
for i in range(1, 501):
    ref = f"PROP{str(i).zfill(4)}"
    ward = random.choice(wards)
    ptype = random.choices(property_types, weights=[60, 25, 15])[0]
    bedrooms = random.choices([1, 2, 3, 4], weights=[10, 25, 50, 15])[0]
    epc = random.choices(epc_ratings, weights=epc_weights)[0]
    build_year = random.randint(1920, 2020)
    is_decent = 0 if epc in ['D', 'E'] and random.random() < 0.3 else 1
    properties.append((ref, ward, ptype, bedrooms, epc, build_year, is_decent))

cursor.executemany(
    "INSERT INTO Properties VALUES (?,?,?,?,?,?,?)",
    properties
)
conn.commit()
print(f"  {len(properties)} properties inserted.")

# ============================================================
# REPAIR JOBS STAGING
# ============================================================
print("Generating Repair Jobs...")

categories = list(range(1, 13))
contractors = [1, 2, 3]

# Three priority bands -- Urgent added to support Awaab's Law
# three-tier compliance RAG in GetRepairsByCategory
priorities = ['Emergency', 'Urgent', 'Non-Emergency']
priority_weights_standard = [15, 10, 75]   # Non-damp jobs
priority_weights_damp     = [15, 30, 55]   # Damp/Mould jobs weighted toward Urgent
                                            # -- reflects Awaab's Law reporting reality

# No Access added to surface compliance exposure
# Weighted higher for Damp/Mould -- failed access on a damp
# job keeps the legal clock running under Awaab's Law
statuses_standard = ['Completed', 'In Progress', 'Cancelled', 'No Access']
weights_standard  = [85, 8, 4, 3]

statuses_damp     = ['Completed', 'In Progress', 'Cancelled', 'No Access']
weights_damp      = [78, 8, 4, 10]   # ~10% No Access for damp jobs vs ~3% elsewhere

# Awaab's Law: damp/mould jobs weighted to winter months
# Categories 1 (Damp and Mould) and 2 (Condensation) = Damp/Mould group
def pick_category(raised_date):
    if raised_date.month in [11, 12, 1, 2, 3]:
        return random.choices(categories, weights=[20, 10, 15, 10, 8, 5, 8, 8, 6, 4, 4, 2])[0]
    else:
        return random.choices(categories, weights=[8, 5, 10, 8, 10, 8, 12, 12, 10, 8, 6, 3])[0]

# Contractor assignment respects ContractType from reference data:
#   Mears (1)        = Both      -- Emergency and Planned
#   Equans (2)       = Planned   -- Non-Emergency only
#   Direct Works (3) = Emergency -- Emergency only
def pick_contractor(priority):
    if priority == 'Emergency':
        return random.choices([1, 3], weights=[60, 40])[0]
    else:
        # Urgent and Non-Emergency both treated as Planned work
        return random.choices([1, 2], weights=[50, 50])[0]

# Three-band completion targets aligned to Awaab's Law thresholds:
#   Emergency:     1 day
#   Urgent:        14 days
#   Non-Emergency: 20 days
def days_to_complete(priority, status):
    if status != 'Completed':
        # No Access, Cancelled, In Progress -- no completion date
        return None
    if priority == 'Emergency':
        # ~99% within 1 day -- small breach tail for realism
        return random.choices(
            [random.randint(1, 1), random.randint(2, 5)],
            weights=[99, 1]
        )[0]
    elif priority == 'Urgent':
        # ~96% within 14 days -- Awaab's Law urgent threshold
        return random.choices(
            [random.randint(1, 14), random.randint(15, 30)],
            weights=[96, 4]
        )[0]
    else:
        # Non-Emergency: ~98% within 20 days
        return random.choices(
            [random.randint(1, 20), random.randint(21, 40)],
            weights=[98, 2]
        )[0]

staging_rows = []
for i in range(1000):
    prop = random.choice(properties)[0]
    raised = start_date + timedelta(days=random.randint(0, delta.days))
    category = pick_category(raised)

    # Apply damp-weighted priority and status distributions
    # where category is Damp and Mould (1) or Condensation (2)
    is_damp = category in [1, 2]

    priority = random.choices(
        priorities,
        weights=priority_weights_damp if is_damp else priority_weights_standard
    )[0]

    status = random.choices(
        statuses_damp if is_damp else statuses_standard,
        weights=weights_damp if is_damp else weights_standard
    )[0]

    contractor = pick_contractor(priority)
    days = days_to_complete(priority, status)
    completed = raised + timedelta(days=days) if days else None

    # Right first time: 95.7% per Rotherham published figure
    rft = None
    if status == 'Completed':
        rft = 1 if random.random() < 0.957 else 0

    # Satisfaction score: weighted toward 4-5
    sat = None
    if status == 'Completed':
        sat = random.choices([1, 2, 3, 4, 5], weights=[2, 3, 10, 35, 50])[0]

    staging_rows.append((
        prop, category, priority, raised, completed,
        contractor, status, rft, sat
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
# ============================================================
print("Loading RepairJobs from staging...")

# Filter updated to include Urgent priority and No Access status
cursor.execute("""
    INSERT INTO RepairJobs
    (JobID, PropertyRef, CategoryID, Priority, DateRaised, DateCompleted,
     ContractorID, Status, RightFirstTime, TenantSatisfactionScore)
    SELECT
        JobID, PropertyRef, CategoryID, Priority, DateRaised, DateCompleted,
        ContractorID, Status, RightFirstTime, TenantSatisfactionScore
    FROM RepairJobs_Staging
    WHERE PropertyRef IS NOT NULL
      AND CategoryID IS NOT NULL
      AND Priority IN ('Emergency', 'Urgent', 'Non-Emergency')
      AND Status IN ('Completed', 'In Progress', 'Cancelled', 'No Access')
""")
conn.commit()

row_count = cursor.execute("SELECT COUNT(*) FROM RepairJobs").fetchone()[0]
print(f"  {row_count} rows loaded into RepairJobs.")

cursor.close()
conn.close()
print("\nDone. Database populated.")
