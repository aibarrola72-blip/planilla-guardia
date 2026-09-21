"""Conteos y sanidad de los datos migrados."""
import os

import psycopg

with psycopg.connect(os.environ["SUPABASE_DB_CONNECTION"]) as conn, conn.cursor() as cur:
    cur.execute("select (select count(*) from personas), (select count(*) from vacaciones), (select count(*) from libres), (select count(*) from plan_mensual), (select count(*) from unidades), (select count(*) from sectores), (select count(*) from cargos), (select count(*) from turnos)")
    col = ["personas", "vacaciones", "libres", "plan_mensual", "unidades", "sectores", "cargos", "turnos"]
    fila = cur.fetchone()
    for nombre, valor in zip(col, fila):
        print(f"{nombre}={valor}", end="  ")
    print()
    cur.execute("select min(fecha), max(fecha) from plan_mensual")
    print("plan_mensual fechas:", cur.fetchone())
    cur.execute("select count(*) from personas where estado='ACTIVO'")
    print("personas ACTIVO:", cur.fetchone()[0])
    cur.execute("select email from auth.users")
    print("usuarios auth:", [r[0] for r in cur.fetchall()])
    cur.execute("select user_id is not null, rol from perfiles")
    print("perfiles:", cur.fetchall())