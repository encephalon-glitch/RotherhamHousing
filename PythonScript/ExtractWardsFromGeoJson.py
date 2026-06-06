# Extracts Rotherham MBC ward boundaries from the ONS full UK ward boundary file.
# URL: https://geoportal.statistics.gov.uk/datasets/wards-may-2024-boundaries-uk-bfc-2/explore?location=55.340000%2C-3.316939%2C6&showTable=true
# Filters on WD24CD range: E05012993-E05013017
# Output preserves full source file structure

import json
import os
# Variables
SOURCE = r"<ReplaceWithFullFilePath>"
SAVEaS = r"<ReplaceWithFullFilePath>"
if os.path.exists(SAVEaS):
    print(f"Existing file found -- overwriting.")

    
'''rotherham_wards = [
    'Anston & Woodsetts', 'Aston & Todwick', 'Aughton & Swallownest',
    'Boston Castle', 'Bramley & Ravenfield', 'Brinsworth',
    'Dalton & Thrybergh', 'Dinnington', 'Greasbrough',
    'Hellaby & Maltby West', 'Hoober', 'Keppel',
    'Kilnhurst & Swinton East', 'Maltby East', 'Rawmarsh East',
    'Rawmarsh West', 'Rother Vale', 'Rotherham East',
    'Rotherham West', 'Sitwell', 'Swinton Rockingham',
    'Thurcroft & Wickersley South', 'Wales', 'Wath',
    'Wickersley North'
]
'''

print("Reading source file, please wait...")
with open(SOURCE, encoding="utf-8") as f:
    data = json.load(f)

filtered = [
    feature for feature in data["features"]
    if "E05012993" <= feature["properties"].get("WD24CD", "") <= "E05013017"
]

'''filtered = [
    feature for feature in data["features"]
    if feature["properties"].get("WD24NM") in rotherham_wards
]
'''

print(f"\nFound {len(filtered)} of 25 expected wards.")

if len(filtered) != 25:
    print("Warning: unexpected ward count -- check source file.")
else:
    print("All 25 wards found.")

'''found_names = {f["properties"]["WD24NM"] for f in filtered}
missing     = [w for w in rotherham_wards if w not in found_names]

print(f"\nFound {len(filtered)} of {len(rotherham_wards)} expected wards.")

if missing:
    print("\nMissing wards:")
    for w in missing:
        print(f"  {w}")
else:
    print("All 25 wards found.")
'''

output = {**data, "features": filtered}

with open(SAVEaS, "w", encoding="utf-8") as f:
    json.dump(output, f)

print(f"\nSaved {len(filtered)} wards to {SAVEaS}")
