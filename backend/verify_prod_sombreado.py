import requests, re
from app import config

anon = {"apikey": config.SUPABASE_ANON_KEY}
url = "https://ineram-reportes.onrender.com/reporte?anio=2026&mes=9&formato=html"
r = requests.get(url, headers=anon, timeout=60)
print("status", r.status_code)
h = r.text
print("celda-libre      :", h.count('celda-libre'))
print("celda-fin-semana :", h.count('celda-fin-semana'))
print("celda-turno      :", h.count('celda-turno'))
m = re.findall(r'celda-(libre|fin-semana)', h)
print("proporcion (primeras 60):", m[:60])
