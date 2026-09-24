-- ============================================================
-- INERAM - Unidades a cargo por usuario (jefes con varias unidades)
-- Permite que un 'jefe' tenga varias unidades a su cargo. La tabla
-- public.perfil_unidades es la fuente de verdad del alcance; se siembra
-- desde public.perfiles.unidad_id (que se conserva como "primaria").
-- El RLS pasa de mi_unidad() (una) a mi_unidades() (conjunto).
-- ============================================================

-- ---------- Tabla usuario-unidad ----------
create table if not exists public.perfil_unidades (
  user_id    uuid not null references auth.users(id) on delete cascade,
  unidad_id  bigint not null references public.unidades(id) on delete cascade,
  primary key (user_id, unidad_id)
);

-- Backfill: los que tenían unidad en 'perfiles' pasan a perfil_unidades.
insert into public.perfil_unidades (user_id, unidad_id)
select user_id, unidad_id from public.perfiles
where unidad_id is not null
on conflict do nothing;

alter table public.perfil_unidades enable row level security;

drop policy if exists "dunidades.lectura_propia" on public.perfil_unidades;
drop policy if exists "dunidades.gestion" on public.perfil_unidades;

-- Lectura: el usuario ve sus unidades; admin/jefe_enfermeria todas.
create policy "dunidades.lectura_propia" on public.perfil_unidades for select to authenticated
  using (es_admin() or es_jefe_enfermeria() or auth.uid() = user_id);

-- Escritura: solo admin / jefe_enfermeria (los jefes no cambian alcances).
create policy "dunidades.gestion" on public.perfil_unidades for all to authenticated
  using (es_admin() or es_jefe_enfermeria())
  with check (es_admin() or es_jefe_enfermeria());

-- ---------- mi_unidades(): unidades a cargo del usuario ----------
-- Si el usuario no tiene filas en perfil_unidades (p. ej. RT por
-- invitación), cae a perfiles.unidad_id para no romper el flujo único.
create or replace function public.mi_unidades()
returns setof bigint
language sql
stable
security definer
set search_path = public
as $$
  select pu.unidad_id from public.perfil_unidades pu where pu.user_id = auth.uid()
  union
  select p.unidad_id from public.perfiles p
  where p.user_id = auth.uid() and p.unidad_id is not null
    and not exists (select 1 from public.perfil_unidades x where x.user_id = auth.uid());
$$;

-- ---------- RLS existentes: de mi_unidad() a mi_unidades() ----------

-- personas: lectura y edición por unidad
drop policy if exists "per.personas_read" on public.personas;
create policy "per.personas_read" on public.personas for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or ((es_jefe() or es_rt()) and unidad_id in (select public.mi_unidades()))
  );

drop policy if exists "per.personas_write_unidad" on public.personas;
create policy "per.personas_write_unidad" on public.personas for all to authenticated
  using (es_jefe() and (unidad_id in (select public.mi_unidades()) or unidad_id is null))
  with check (es_jefe() and unidad_id in (select public.mi_unidades()));

-- vacaciones y libres
drop policy if exists "aus.vacaciones_read" on public.vacaciones;
create policy "aus.vacaciones_read" on public.vacaciones for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id in (select public.mi_unidades())))
  );

drop policy if exists "aus.vacaciones_write_unidad" on public.vacaciones;
create policy "aus.vacaciones_write_unidad" on public.vacaciones for all to authenticated
  using ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id in (select public.mi_unidades())))
  with check ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id in (select public.mi_unidades())));

drop policy if exists "aus.libres_read" on public.libres;
create policy "aus.libres_read" on public.libres for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id in (select public.mi_unidades())))
  );

drop policy if exists "aus.libres_write_unidad" on public.libres;
create policy "aus.libres_write_unidad" on public.libres for all to authenticated
  using ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id in (select public.mi_unidades())))
  with check ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id in (select public.mi_unidades())));

-- plan_mensual: lectura/edición por unidad
drop policy if exists "plan.read" on public.plan_mensual;
create policy "plan.read" on public.plan_mensual for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = plan_mensual.persona_id and p.unidad_id in (select public.mi_unidades())))
  );

drop policy if exists "plan.write_unidad" on public.plan_mensual;
create policy "plan.write_unidad" on public.plan_mensual for all to authenticated
  using (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = plan_mensual.persona_id and p.unidad_id in (select public.mi_unidades())))
  with check (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = plan_mensual.persona_id and p.unidad_id in (select public.mi_unidades())));

-- perfiles: el jefe gestiona RTs de sus unidades
drop policy if exists "perf.gestion_rt_unidad" on public.perfiles;
create policy "perf.gestion_rt_unidad" on public.perfiles for all to authenticated
  using (es_jefe() and rol = 'rt' and unidad_id in (select public.mi_unidades()))
  with check (es_jefe() and rol = 'rt' and unidad_id in (select public.mi_unidades()));

-- ---------- Permisos PostgREST (idempotentes) ----------
grant all privileges on table public.perfil_unidades to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;