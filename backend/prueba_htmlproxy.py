import requests, re
from app import config

anon = {"apikey": config.SUPABASE_ANON_KEY}
r = requests.get("https://ineram-reportes.onrender.com/reporte?anio=2026&mes=9&formato=html",
                 headers=anon, timeout=60)
print("reporte prod ->", r.status_code)
html = r.text
print("celda-libre (css+uso):", html.count('celda-libre'))
m = re.search(r'<td class="celda-libre"[^>]*>[^<]*</td>', html)
print("ejemplo:", m.group(0) if m else "ninguno")
