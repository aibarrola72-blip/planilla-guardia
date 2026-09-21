"""Crea un usuario de Supabase Auth directamente en BD (rol 'jefe' vía trigger).

Uso: setear SUPABASE_DB_CONNECTION y correr
     python crear_usuario.py <email> <password>
"""
import os
import sys

import psycopg


def principal() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("uso: crear_usuario.py <email> <password>")
    email, password = sys.argv[1], sys.argv[2]

    sql = """
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, confirmation_sent_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(), 'authenticated', 'authenticated',
  %s, crypt(%s, gen_salt('bf')),
  now(), now(),
  '{"provider":"email","providers":["email"]}', '{}',
  now(), now(), '', ''
);
"""
    with psycopg.connect(os.environ["SUPABASE_DB_CONNECTION"]) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (email, password))
    print(f"Usuario creado: {email} (perfil 'jefe' generado por trigger).")


if __name__ == "__main__":
    principal()