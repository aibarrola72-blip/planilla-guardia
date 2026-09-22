"""Diagnóstico del esquema auth para el login (error 'querying schema')."""
import os

import psycopg

with psycopg.connect(os.environ["SUPABASE_DB_CONNECTION"]) as conn, conn.cursor() as cur:
    cur.execute("select email, id, instance_id, encrypted_password is not null as tiene_pass from auth.users")
    print("auth.users:", cur.fetchall())
    cur.execute("select id, user_id, provider, identity_data->>'email' from auth.identities")
    print("auth.identities:", cur.fetchall())
    cur.execute("select count(*) from auth.identities")
    print("n identidades:", cur.fetchone()[0])
    cur.execute("select function_schema, proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where proname in ('es_jefe','handle_new_user')")
    print("funciones:", cur.fetchall())
    cur.execute("select event_object_schema, event_object_table, trigger_name, action_timing from information_schema.triggers where event_object_table='users'")
    print("triggers sobre auth.users:", cur.fetchall())
    cur.execute("select has_schema_privilege('supabase_auth_admin','auth','USAGE'), has_table_privilege('supabase_auth_admin','auth.users','SELECT'), has_table_privilege('supabase_auth_admin','auth.identities','SELECT')")
    print("privilegios supabase_auth_admin (auth usage / users / identities):", cur.fetchone())
    cur.execute("select table_name from information_schema.tables where table_schema='auth' order by table_name")
    auth_tablas = [r[0] for r in cur.fetchall()]
    print("tablas auth:", auth_tablas)