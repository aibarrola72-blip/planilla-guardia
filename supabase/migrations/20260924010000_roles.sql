-- ============================================================
-- INERAM - Modelo de roles y permisos por rol/unidad
-- Roles: 'admin', 'jefe_enfermeria', 'jefe' (de unidad), 'rt'
--  - admin       (IT, gestiona por web): control total
--  - jefe_enfermeria: supervisa jefes de unidad. Catálogos y
--    personal global, planilla en SOLO lectura.
--  - jefe: opera su unidad (plan, personal, ausencias, reportes)
--    y gestiona los RT de su unidad.
--  - rt: solo carga de libres y vacaciones (de su unidad).
-- Alta de usuarios SOLO por invitación: el trigger asigna 'rt' y
-- el perfil es completado (rol/unidad/activo) por el admin (web)
-- o el jefe de unidad (para sus RT).
-- ============================================================

-- ---------- perfiles: ampliar roles y estado ----------
alter table public.perfiles
  drop constraint if exists perfiles_rol_check;

alter table public.perfiles
  add constraint perfiles_rol_check
    check (rol in ('admin', 'jefe_enfermeria', 'jefe', 'rt'));

alter table public.perfiles
  add column activo boolean not null default true,
  add column updated_at timestamptz not null default now();

-- ---------- Funciones de rol para RLS ----------
-- Seguridad: son security definer para consultar perfiles
-- (superando el RLS de perfiles, que excluye a otros usuarios).

create or replace function public.mi_rol()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.rol
  from public.perfiles p
  where p.user_id = auth.uid()
$$;

create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.rol = 'admin' and p.activo
                   from public.perfiles p
                   where p.user_id = auth.uid()), false)
$$;

create or replace function public.es_jefe_enfermeria()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.rol = 'jefe_enfermeria' and p.activo
                   from public.perfiles p
                   where p.user_id = auth.uid()), false)
$$;

--- jefe de unidad
create or replace function public.es_jefe()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.rol = 'jefe' and p.activo
                   from public.perfiles p
                   where p.user_id = auth.uid()), false)
$$;

create or replace function public.es_rt()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.rol = 'rt' and p.activo
                   from public.perfiles p
                   where p.user_id = auth.uid()), false)
$$;

-- Unidad del usuario autenticado (null para admin/enfermeria).
create or replace function public.mi_unidad()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select p.unidad_id
  from public.perfiles p
  where p.user_id = auth.uid()
$$;

-- ---------- RLS: catálogos (unidades, sectores, cargos, turnos) ----------
-- SELECT: admin / jefe_enfermeria / jefe (rt NO ve catálogos)
-- ESCRITURA: admin / jefe_enfermeria

drop policy if exists "jefes gestionan unidades" on public.unidades;
drop policy if exists "jefes gestionan sectores" on public.sectores;
drop policy if exists "jefes gestionan cargos" on public.cargos;
drop policy if exists "jefes gestionan turnos" on public.turnos;

create policy "cls.catalogos_read"  on public.unidades for select to authenticated
  using (es_admin() or es_jefe_enfermeria() or es_jefe());
create policy "cls.catalogos_write" on public.unidades for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

create policy "cls.sectores_read"  on public.sectores for select to authenticated
  using (es_admin() or es_jefe_enfermeria() or es_jefe());
create policy "cls.sectores_write" on public.sectores for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

create policy "cls.cargos_read"  on public.cargos for select to authenticated
  using (es_admin() or es_jefe_enfermeria() or es_jefe());
create policy "cls.cargos_write" on public.cargos for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

create policy "cls.turnos_read"  on public.turnos for select to authenticated
  using (es_admin() or es_jefe_enfermeria() or es_jefe());
create policy "cls.turnos_write" on public.turnos for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

-- ---------- RLS: personas ----------
drop policy if exists "jefes gestionan personal" on public.personas;

-- Lectura: admin/enfermeria ven todo; jefe y rt ven solo su unidad.
create policy "per.personas_read" on public.personas for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or ((es_jefe() or es_rt()) and mi_unidad() is not null and unidad_id = mi_unidad())
  );

-- Alta/baja/edición: admin / jefe_enfermeria global.
create policy "per.personas_write_admin" on public.personas for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

-- Edición por el jefe de su unidad (RT no gestiona personal).
create policy "per.personas_write_unidad" on public.personas for all to authenticated
  using (es_jefe() and mi_unidad() is not null and (unidad_id = mi_unidad() or unidad_id is null))
  with check (es_jefe() and mi_unidad() is not null and unidad_id = mi_unidad());

-- ---------- RLS: vacaciones y libres ----------
drop policy if exists "jefes gestionan vacaciones" on public.vacaciones;
drop policy if exists "jefes gestionan libres" on public.libres;

create policy "aus.vacaciones_read" on public.vacaciones for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or ((es_jefe() or es_rt()) and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id = mi_unidad()))
  );
create policy "aus.vacaciones_write_admin" on public.vacaciones for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());
create policy "aus.vacaciones_write_unidad" on public.vacaciones for all to authenticated
  using ((es_jefe() or es_rt()) and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id = mi_unidad()))
  with check ((es_jefe() or es_rt()) and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id = mi_unidad()));

create policy "aus.libres_read" on public.libres for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or ((es_jefe() or es_rt()) and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id = mi_unidad()))
  );
create policy "aus.libres_write_admin" on public.libres for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());
create policy "aus.libres_write_unidad" on public.libres for all to authenticated
  using ((es_jefe() or es_rt()) and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id = mi_unidad()))
  with check ((es_jefe() or es_rt()) and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id = mi_unidad()));

-- ---------- RLS: plan_mensual ----------
drop policy if exists "jefes gestionan plan" on public.plan_mensual;

-- Lectura: admin, jefe_enfermeria (supervisión) y jefe de la unidad.
create policy "plan.read" on public.plan_mensual for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_jefe() and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = plan_mensual.persona_id and p.unidad_id = mi_unidad()))
  );

-- Edición: solo admin y jefe de su unidad (enfermeria NO planifica).
create policy "plan.write_admin" on public.plan_mensual for all to authenticated
  using (es_admin())
  with check (es_admin());
create policy "plan.write_unidad" on public.plan_mensual for all to authenticated
  using (es_jefe() and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = plan_mensual.persona_id and p.unidad_id = mi_unidad()))
  with check (es_jefe() and mi_unidad() is not null and exists (
          select 1 from public.personas p
          where p.id = plan_mensual.persona_id and p.unidad_id = mi_unidad()));

-- ---------- RLS: perfiles ----------
drop policy if exists "perfil propio" on public.perfiles;

-- Cada usuario lee su propio perfil (para conocer rol/unidad/activo).
create policy "perf.lectura_propia" on public.perfiles for select to authenticated
  using (auth.uid() = user_id);

-- Admin y jefe_enfermeria gestionan todos los perfiles.
create policy "perf.gestion_admin" on public.perfiles for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

-- El jefe de unidad gestiona SOLO los perfiles rol='rt' de su unidad.
create policy "perf.gestion_rt_unidad" on public.perfiles for all to authenticated
  using (es_jefe() and rol = 'rt' and unidad_id = mi_unidad())
  with check (es_jefe() and rol = 'rt' and unidad_id = mi_unidad());

-- ---------- Trigger: nuevo usuario → rol 'rt' ----------
-- (el alta pública queda deshabilitada; los usuarios llegan por
-- invitación del admin/web o del jefe de unidad para sus RT).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfiles (user_id, rol)
  values (new.id, 'rt');
  return new;
end;
$$;

-- ---------- Backfill ----------
-- Los 'jefe' existentes quedan como jefe de unidad (rol ya válido).
-- El rol 'admin' inicial se asigna con migracion/crear_admin.py
-- (no se hardcodea aquí para no fugar el email del administrador).

-- ---------- Permisos PostgREST ----------
-- El hosted de Supabase otorga estos permisos automáticamente; en local/CLI
-- hacen falta declararlos para que anon/authenticated/service_role puedan
-- operar sobre las tablas de migraciones. Son idempotentes.
grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables in schema public to anon, authenticated, service_role;
grant all privileges on all sequences in schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;