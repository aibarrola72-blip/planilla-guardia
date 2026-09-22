"""Recrea un usuario de Supabase Auth correctamente (Admin API) y prueba el login.

La creación manual en auth.users dejó auth.identities vacía, lo que hace
fallar go_true con 'Database error querying schema'.

Uso (env): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_DB_CONNECTION
        python recrear_usuario.py <email> <password>
"""
import os
import sys

import psycopg
import requests

EMAIL = sys.argv[1]
PASSWORD = sys.argv[2]

BASE = os.environ["SUPABASE_URL"].rstrip("/")
ROOT = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
H_AUTH = {"apikey": ROOT, "Authorization": f"Bearer {ROOT}"}


def borrar_existente() -> list[str]:
    con = os.environ["SUPABASE_DB_CONNECTION"]
    with psycopg.connect(con) as conn, conn.cursor() as cur:
        cur.execute("select id from auth.users where email = %s", (EMAIL,))
        ids = [str(r[0]) for r in cur.fetchall()]
        for uid in ids:
            cur.execute("delete from auth.users where id = %s", (uid,))
            print(f"  usuario {EMAIL} ({uid}) eliminado (y dependencias)")
    return ids


def crear_admin_api() -> requests.Response:
    r = requests.post(
        f"{BASE}/auth/v1/admin/users",
        headers={**H_AUTH, "Content-Type": "application/json"},
        json={"email": EMAIL, "password": PASSWORD, "email_confirm": True},
        timeout=60,
    )
    print(f"  admin create -> HTTP {r.status_code}")
    if r.status_code >= 400:
        print(r.text[:1000])
    return r


def probar_login() -> None:
    r = requests.post(
        f"{BASE}/auth/v1/token?grant_type=password",
        headers={"apikey": ROOT, "Content-Type": "application/json"},
        json={"email": EMAIL, "password": PASSWORD},
        timeout=60,
    )
    if r.status_code == 200:
        j = r.json()
        print(f"LOGIN OK -> {j['user']['email']} (id {j['user']['id']})")
    else:
        print(f"LOGIN FAIL -> HTTP {r.status_code}: {r.text[:400]}")


if __name__ == "__main__":
    borrar_existente()
    crear_admin_api()
    probar_login()