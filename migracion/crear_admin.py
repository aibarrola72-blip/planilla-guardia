"""Crea (o reajusta) el usuario administrador inicial de INERAM.

Asigna rol='admin' en public.perfiles. El rol 'admin' gestiona todo el
sistema desde el panel web del backend (no existe en la app móvil).

Uso (env):
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_DB_CONNECTION
    ADMIN_EMAIL, ADMIN_PASSWORD   (opcional: si no se pasa, no crea el
    usuario, solo asigna el rol al email existente)

    python crear_admin.py
"""
import os
import sys

import psycopg
import requests

EMAIL = os.environ.get("ADMIN_EMAIL")
PASSWORD = os.environ.get("ADMIN_PASSWORD")

BASE = os.environ.get("SUPABASE_URL", "").rstrip("/")
ROOT = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
DSN = os.environ.get("SUPABASE_DB_CONNECTION", "")


def _h_auth() -> dict:
    return {"apikey": ROOT, "Authorization": f"Bearer {ROOT}", "Content-Type": "application/json"}


def crear_usuario_si_hay_credenciales() -> str | None:
    """Crea el usuario por Admin API si hay email+password. Devuelve su id."""
    if not (EMAIL and PASSWORD):
        print("ADMIN_PASSWORD no seteado: solo se asignará rol a un usuario existente.")
        return None

    # Si ya existe, se borra (mismo criterio que recrear_usuario.py).
    if DSN:
        with psycopg.connect(DSN) as conn, conn.cursor() as cur:
            cur.execute("select id from auth.users where email = %s", (EMAIL,))
            ids = [str(r[0]) for r in cur.fetchall()]
            for uid in ids:
                cur.execute("delete from auth.users where id = %s", (uid,))
                print(f"  usuario existente {EMAIL} ({uid}) eliminado")
    else:
        print("  sin SUPABASE_DB_CONNECTION: no se limpia usuario previo")

    r = requests.post(f"{BASE}/auth/v1/admin/users", headers=_h_auth(),
                      json={"email": EMAIL, "password": PASSWORD, "email_confirm": True}, timeout=60)
    print(f"  admin create -> HTTP {r.status_code}")
    if r.status_code >= 400:
        print(r.text[:800])
        sys.exit(1)
    return r.json().get("id")


def asignar_rol_admin(user_id: str | None) -> None:
    """Pone rol='admin', activo=true en perfiles para el email indicado."""
    if not DSN:
        print("ERROR: hace falta SUPABASE_DB_CONNECTION para asignar el rol.")
        sys.exit(1)
    if not EMAIL:
        print("ERROR: hace falta ADMIN_EMAIL.")
        sys.exit(1)

    with psycopg.connect(DSN) as conn, conn.cursor() as cur:
        # Asegura que exista el perfil (el trigger lo crea al crear el user).
        cur.execute("""
            insert into public.perfiles (user_id, rol, activo)
            select u.id, 'admin', true
            from auth.users u
            where u.email = %s
              and not exists (select 1 from public.perfiles p where p.user_id = u.id)
        """, (EMAIL,))
        cur.execute("""
            update public.perfiles p
            set rol = 'admin', activo = true, updated_at = now()
            from auth.users u
            where p.user_id = u.id and u.email = %s
        """, (EMAIL,))
        print(f"  perfiles actualizados: {cur.rowcount} (rol=admin, activo)")

        cur.execute("""
            select p.rol, p.activo from public.perfiles p
            join auth.users u on u.id = p.user_id where u.email = %s
        """, (EMAIL,))
        fila = cur.fetchone()
        print(f"  verificación -> rol={fila[0]!r} activo={fila[1]}")


if __name__ == "__main__":
    if not BASE or not ROOT:
        print("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.")
        sys.exit(1)
    uid = crear_usuario_si_hay_credenciales()
    asignar_rol_admin(uid)
    print("Listo: admin inicial preparado.")
