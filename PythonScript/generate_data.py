import pyodbc
import pandas as pd
from faker import Faker
import random
from datetime import date, timedelta

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
priorities = ['Emergency', 'Non-Emergency']
priority_weights = [15, 85]
statuses = ['Completed', 'In Progress', 'Cancelled']
status_weights = [88, 8, 4]

# Awaabs Law: damp/mould jobs weighted to winter months
def pick_category(raised_date):
    if raised_date.month in [11, 12, 1, 2, 3]:
        return random.choices(categories, weights=[20, 10, 15, 10, 8, 5, 8, 8, 6, 4, 4, 2])[0]
    else:
        return random.choices(categories, weights=[8, 5, 10, 8, 10, 8, 12, 12, 10, 8, 6, 3])[0]

def pick_contractor(priority):
    if priority == 'Emergency':
        return random.choices([1, 3], weights=[60, 40])[0]
    else:
        return random.choices([1, 2], weights=[50, 50])[0]

def days_to_complete(priority, status):
    if status != 'Completed':
        return None
    if priority == 'Emergency':
        # Target: complete within 1 working day
        # ~99% on target, small number breach
        return random.choices(
            [random.randint(1, 1), random.randint(2, 5)],
            weights=[99, 1]
        )[0]
    else:
        # Target: complete within 20 working days
        # ~98% on target
        return random.choices(
            [random.randint(1, 20), random.randint(21, 40)],
            weights=[98, 2]
        )[0]

staging_rows = []
for i in range(1000):
    prop = random.choice(properties)[0]
    raised = start_date + timedelta(days=random.randint(0, delta.days))
    priority = random.choices(priorities, weights=priority_weights)[0]
    category = pick_category(raised)
    contractor = pick_contractor(priority)
    status = random.choices(statuses, weights=status_weights)[0]
    days = days_to_complete(priority, status)
    completed = raised + timedelta(days=days) if days else None

    # Right first time: 95.7% per their published figure
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
      AND Priority IN ('Emergency', 'Non-Emergency')
      AND Status IN ('Completed', 'In Progress', 'Cancelled')
""")
conn.commit()

row_count = cursor.execute("SELECT COUNT(*) FROM RepairJobs").fetchone()[0]
print(f"  {row_count} rows loaded into RepairJobs.")

cursor.close()
conn.close()
print("\nDone. Database populated.")