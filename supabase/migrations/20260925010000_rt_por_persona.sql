-- ============================================================
-- INERAM - RT responsable de turno vinculado a una persona
-- El RT queda enlazado a una persona de la planilla (unidad+turno).
-- Su alcance en planilla/ausencias pasa de "toda su unidad" a
-- "su unidad Y su turno". Si no tiene persona (mi_turno() null)
-- se conserva el comportamiento anterior (toda la unidad).
-- ============================================================

-- ---------- vinculo RT -> persona ----------
alter table public.perfiles
  add column if not exists persona_id bigint references public.personas(id) on delete set null;

create index if not exists perfiles_persona_id_idx on public.perfiles(persona_id);

-- ---------- mi_turno(): turno del RT según su persona ----------
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
  where p.user_id = auth.uid();
$$;

-- ---------- RLS: RT opera unidad Y turno ----------
-- Regla compartida: para RT, la persona debe estar en una unidad del
-- usuario y, si el RT tiene persona/turno, en el mismo turno.
-- Para jefe/consulta se conserva el alcance por unidad.

-- personas
drop policy if exists "per.personas_read" on public.personas;
create policy "per.personas_read" on public.personas for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_rt() and unidad_id in (select public.mi_unidades())
        and (public.mi_turno() is null or turno_id = public.mi_turno()))
    or (es_jefe() and unidad_id in (select public.mi_unidades()))
  );

-- vacaciones y libres
drop policy if exists "aus.vacaciones_read" on public.vacaciones;
create policy "aus.vacaciones_read" on public.vacaciones for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_rt() and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (public.mi_turno() is null or p.turno_id = public.mi_turno())))
    or (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id and p.unidad_id in (select public.mi_unidades())))
  );

drop policy if exists "aus.vacaciones_write_unidad" on public.vacaciones;
create policy "aus.vacaciones_write_unidad" on public.vacaciones for all to authenticated
  using ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt() or public.mi_turno() is null or p.turno_id = public.mi_turno())))
  with check ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = vacaciones.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt() or public.mi_turno() is null or p.turno_id = public.mi_turno())));

drop policy if exists "aus.libres_read" on public.libres;
create policy "aus.libres_read" on public.libres for select to authenticated
  using (
    es_admin() or es_jefe_enfermeria()
    or (es_rt() and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (public.mi_turno() is null or p.turno_id = public.mi_turno())))
    or (es_jefe() and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id and p.unidad_id in (select public.mi_unidades())))
  );

drop policy if exists "aus.libres_write_unidad" on public.libres;
create policy "aus.libres_write_unidad" on public.libres for all to authenticated
  using ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt() or public.mi_turno() is null or p.turno_id = public.mi_turno())))
  with check ((es_jefe() or es_rt()) and exists (
          select 1 from public.personas p
          where p.id = libres.persona_id
            and p.unidad_id in (select public.mi_unidades())
            and (not es_rt() or public.mi_turno() is null or p.turno_id = public.mi_turno())));

-- ---------- Permisos (idempotentes) ----------
grant execute on function public.mi_turno() to anon, authenticated;
grant all privileges on table public.perfiles to anon, authenticated, service_role;