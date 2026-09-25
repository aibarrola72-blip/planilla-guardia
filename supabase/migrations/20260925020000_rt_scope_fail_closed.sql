-- ============================================================
-- INERAM - Fail-closed para alcance RT por turno
-- Archivo sugerido: supabase/migrations/20260925020000_rt_scope_fail_closed.sql
-- Aplicar con:  python migracion/aplicar_sql.py <ruta/este_archivo.sql>
-- Validado: 0 personal ACTIVO sin turno (unidades 1 y 2);
--           2 RTs con persona_id NULL (remediar antes de aplicar).
-- Efecto: mi_turno() = NULL  =>  RT NO ve personal (antes: veía toda la unidad).
-- ============================================================

-- ---------- 1) mi_turno(): guard estricto p.rol = 'rt' ----------
-- Sin fila (sin persona) o persona sin turno => NULL => políticas cierran el acceso.
create or replace function public.mi_turno()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select pe.turno_id
  from public.perfiles p
  join public.personas pe on pe.id = p.persona_id
  where p.user_id = auth.uid()
    and p.rol = 'rt';
$$;

-- ---------- 2) personas: lectura ----------
drop policy if exists "per.personas_read" on public.personas;
create policy "per.personas_read" on public.personas for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_rt() and public.mi_turno() is not null
        and unidad_id in (select public.mi_unidades())
        and turno_id = public.mi_turno())
    or (es_jefe() and unidad_id in (select public.mi_unidades()))
  );

-- ---------- 3) vacaciones: lectura ----------
drop policy if exists "aus.vacaciones_read" on public.vacaciones;
create policy "aus.vacaciones_read" on public.vacaciones for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_rt() and public.mi_turno() is not null and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and p.turno_id = public.mi_turno()))
    or (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())))
  );

-- ---------- 4) vacaciones: escritura ----------
drop policy if exists "aus.vacaciones_write_unidad" on public.vacaciones;
create policy "aus.vacaciones_write_unidad" on public.vacaciones for all to authenticated
  using ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt()
                 or (public.mi_turno() is not null and p.turno_id = public.mi_turno()))))
  with check ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt()
                 or (public.mi_turno() is not null and p.turno_id = public.mi_turno()))));

-- ---------- 5) libres: lectura ----------
drop policy if exists "aus.libres_read" on public.libres;
create policy "aus.libres_read" on public.libres for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_rt() and public.mi_turno() is not null and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and p.turno_id = public.mi_turno()))
    or (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())))
  );

-- ---------- 6) libres: escritura ----------
drop policy if exists "aus.libres_write_unidad" on public.libres;
create policy "aus.libres_write_unidad" on public.libres for all to authenticated
  using ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt()
                 or (public.mi_turno() is not null and p.turno_id = public.mi_turno()))))
  with check ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt()
                 or (public.mi_turno() is not null and p.turno_id = public.mi_turno()))));

-- ---------- 7) Permisos (idempotentes) ----------
grant execute on function public.mi_turno() to anon, authenticated;
grant all privileges on table public.perfiles to anon, authenticated, service_role;

-- ---------- 8) Verificación (solo lectura) ----------
-- select polname, pg_get_expr(polqual, polrelid)
--   from pg_policies
--  where polname in ('per.personas_read','aus.vacaciones_read',
--                    'aus.vacaciones_write_unidad','aus.libres_read',
--                    'aus.libres_write_unidad')
--  order by polname;
