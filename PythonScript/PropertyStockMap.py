# PropertyStockMap.py
# Author:   Martin Sefelin
# Version:  1.1
# Purpose:  Generates an interactive ward-level property stock map for Rotherham MBC.
#           Two choropleth layers with toggle:
#             - Decent homes % per ward
#             - EPC composite score per ward (A=5 down to E=1, ward average)
#           Output is a self-contained HTML file suitable for GitHub Pages hosting.
#
# v1.1:     Colour scheme changed to YlGnBu (yellow=lower/warmer, blue=higher/cooler).
#           EPC distribution rendered as an inline HTML histogram in the hover tooltip
#           rather than a flat list of values.

import json
import os
import folium
import pyodbc
import pandas as pd

GEOJSON_PATH = r"C:\Projects\RotherhamHousing\GeoData\rotherham_wards_Extract.geojson"
OUTPUT_PATH  = r"C:\Projects\RotherhamHousing\Visualisation\property_stock_map.html"

# Replace <YourServerName> with your LocalDB instance name.
# Run: sqllocaldb info   to list available instances.
conn_str = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=(localdb)\\MSSQLLocalDB;"
    "DATABASE=RotherhamHousingRepairs;"
    "Trusted_Connection=yes;"
)

SQL = """
SELECT
      WD24CD
    , WD24NM
    , SUM(TotalProperties)                                          AS TotalProperties
    , SUM(CASE WHEN IsDecent = 1 THEN TotalProperties ELSE 0 END)  AS DecentProperties
    , ROUND(
        100.0 * SUM(CASE WHEN IsDecent = 1 THEN TotalProperties ELSE 0 END)
        / NULLIF(SUM(TotalProperties), 0)
      , 1)                                                          AS DecentPct
    , SUM(EPCR_A) AS EPCR_A
    , SUM(EPCR_B) AS EPCR_B
    , SUM(EPCR_C) AS EPCR_C
    , SUM(EPCR_D) AS EPCR_D
    , SUM(EPCR_E) AS EPCR_E
    , ROUND(
        (SUM(EPCR_A)*5.0 + SUM(EPCR_B)*4.0 + SUM(EPCR_C)*3.0
         + SUM(EPCR_D)*2.0 + SUM(EPCR_E)*1.0)
        / NULLIF(SUM(TotalProperties), 0)
      , 2)                                                          AS EPCScore
FROM dbo.vw_PropertyStats
GROUP BY WD24CD, WD24NM
ORDER BY WD24NM
"""


def build_epc_tooltip_html(ward_name, total, decent_pct, epc_score, a, b, c, d, e):
    """Builds an HTML tooltip card with an inline EPC horizontal bar chart.
    Bar widths are proportional to counts relative to the ward's highest-count rating.
    EPC colours follow the standard efficiency convention: green=A through amber/red=E."""
    labels  = ['A', 'B', 'C', 'D', 'E']
    counts  = [a, b, c, d, e]
    colors  = ['#2d7d1e', '#5aab3e', '#9dcc40', '#f0c020', '#e06020']
    max_cnt = max(counts) if max(counts) > 0 else 1
    bar_max = 80

    bars = ""
    for label, count, color in zip(labels, counts, colors):
        width = max(int((count / max_cnt) * bar_max), 2)
        bars += (
            f'<div style="display:flex;align-items:center;margin:2px 0;">'
            f'<span style="width:12px;font-size:10px;font-weight:600;color:{color};">{label}</span>'
            f'<div style="height:9px;width:{width}px;background:{color};'
            f'border-radius:2px;margin:0 5px;"></div>'
            f'<span style="font-size:10px;color:#555;">{count}</span>'
            f'</div>'
        )

    return (
        f'<div style="font-family:sans-serif;padding:2px;min-width:190px;">'
        f'<div style="font-size:13px;font-weight:600;margin-bottom:2px;">{ward_name}</div>'
        f'<div style="font-size:11px;color:#666;margin-bottom:6px;">'
        f'{total} properties &nbsp;&middot;&nbsp; {decent_pct}% decent'
        f'</div>'
        f'<div style="font-size:9px;color:#999;text-transform:uppercase;'
        f'letter-spacing:0.06em;margin-bottom:4px;">Housing stock: EPC distribution</div>'
        f'{bars}'
        f'<div style="border-top:1px solid #eee;margin-top:5px;padding-top:4px;'
        f'font-size:10px;color:#666;">'
        f'Composite score: <b>{epc_score}</b> / 5.0'
        f'</div>'
        f'</div>'
    )


print("Connecting to database...")
conn   = pyodbc.connect(conn_str)
cursor = conn.cursor()
cursor.execute(SQL)
rows   = cursor.fetchall()
cols   = [col[0] for col in cursor.description]
df     = pd.DataFrame.from_records(rows, columns=cols)
cursor.close()
conn.close()
print(f"  {len(df)} wards loaded.")

# pyodbc returns DECIMAL columns as Python Decimal objects -- convert to float
# so numpy operations inside Folium's choropleth don't raise TypeError
for col in ["TotalProperties", "DecentProperties", "DecentPct",
            "EPCScore", "EPCR_A", "EPCR_B", "EPCR_C", "EPCR_D", "EPCR_E"]:
    df[col] = pd.to_numeric(df[col], errors="coerce")

print("Loading ward boundaries...")
with open(GEOJSON_PATH, encoding="utf-8") as f:
    geojson = json.load(f)
print(f"  {len(geojson['features'])} ward polygons found.")

# Embed SQL metrics and pre-built tooltip HTML into each GeoJSON feature
# so the tooltip layer has everything it needs at render time
df_dict = df.set_index("WD24CD").to_dict("index")
for feature in geojson["features"]:
    code = feature["properties"]["WD24CD"]
    if code in df_dict:
        row = df_dict[code]
        feature["properties"].update(row)
        feature["properties"]["tooltip_html"] = build_epc_tooltip_html(
            row["WD24NM"],
            int(row["TotalProperties"]),
            row["DecentPct"],
            row["EPCScore"],
            int(row["EPCR_A"]), int(row["EPCR_B"]), int(row["EPCR_C"]),
            int(row["EPCR_D"]), int(row["EPCR_E"])
        )

print("Building map...")

# CartoDB Positron: minimal base layer so choropleth colours read clearly
m = folium.Map(
    location=[53.43, -1.34],
    zoom_start=11,
    tiles="CartoDB positron",
    prefer_canvas=True
)

# YlGnBu: yellow=lower (warmer/concerning), blue=higher (cooler/better)
# Both layers use the same colour logic -- higher value = better outcome = blue
folium.Choropleth(
    geo_data=geojson,
    name="Decent homes %",
    data=df,
    columns=["WD24CD", "DecentPct"],
    key_on="feature.properties.WD24CD",
    fill_color="YlGnBu",
    fill_opacity=0.7,
    line_opacity=0.4,
    line_color="#555",
    legend_name="Decent homes (%)",
    nan_fill_color="#ccc",
    show=True
).add_to(m)

folium.Choropleth(
    geo_data=geojson,
    name="EPC composite score",
    data=df,
    columns=["WD24CD", "EPCScore"],
    key_on="feature.properties.WD24CD",
    fill_color="YlGnBu",
    fill_opacity=0.7,
    line_opacity=0.4,
    line_color="#555",
    legend_name="EPC composite score (E=1 through A=5)",
    nan_fill_color="#ccc",
    show=False
).add_to(m)

# Transparent overlay carrying the HTML tooltip -- sits above both choropleth
# layers so hover detail is available regardless of which layer is active
folium.GeoJson(
    geojson,
    name="Ward detail",
    style_function=lambda x: {
        "fillOpacity": 0,
        "weight": 0.8,
        "color": "#444"
    },
    tooltip=folium.GeoJsonTooltip(
        fields=["tooltip_html"],
        aliases=[""],
        labels=False,
        sticky=True,
        style=(
            "background: white;"
            "border: 1px solid #ddd;"
            "border-radius: 4px;"
            "padding: 8px;"
            "box-shadow: 0 1px 4px rgba(0,0,0,0.12);"
        )
    )
).add_to(m)

folium.LayerControl(collapsed=False).add_to(m)

os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
m.save(OUTPUT_PATH)
print(f"  Map saved to {OUTPUT_PATH}")
print("\nDone.")
