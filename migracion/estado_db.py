"""Estado de la BD remota (tablas public + migraciones registradas).

Uso: setear SUPABASE_DB_CONNECTION y correr python estado_db.py
"""
import os

import psycopg

DSN = os.environ["SUPABASE_DB_CONNECTION"]

with psycopg.connect(DSN, connect_timeout=20) as conn, conn.cursor() as cur:
    cur.execute("select table_name from information_schema.tables where table_schema='public' order by table_name")
    print("tablas public:", [r[0] for r in cur.fetchall()])
    try:
        cur.execute("select version from supabase_migrations.schema_migrations order by version")
        print("migraciones:", [r[0] for r in cur.fetchall()])
    except psycopg.errors.UndefinedTable:
        print("migraciones: (schema supabase_migrations no existe)")