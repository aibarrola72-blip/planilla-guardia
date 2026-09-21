"""Aplica un archivo SQL a la base remota de Supabase (vía pooler IPv4).

Uso: setear SUPABASE_DB_CONNECTION y correr
       python aplicar_sql.py <ruta_sql>.sql
"""
import argparse
import os

import psycopg


def principal() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("ruta_sql")
    args = ap.parse_args()

    with psycopg.connect(os.environ["SUPABASE_DB_CONNECTION"], connect_timeout=30) as conn, conn.cursor() as cur:
        with open(args.ruta_sql, encoding="utf-8") as fh:
            sql = fh.read()
        cur.execute(sql)
    print("SQL aplicado correctamente.")


if __name__ == "__main__":
    principal()