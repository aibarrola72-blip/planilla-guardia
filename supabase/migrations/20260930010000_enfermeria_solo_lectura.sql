-- El rol 'jefe_enfermeria' queda en SOLO LECTURA: supervisa datos y
-- genera el reporte, pero no gestiona catálogos, personal, ausencias,
-- perfiles ni alcances. Esas escrituras pasan a ser exclusivas de 'admin'.
--
-- Las políticas de LECTURA no se tocan (cls.*_read, per.personas_read,
-- aus.*_read, plan.read, firmas.read, dunidades.lectura_propia).
-- La app ya no muestra el módulo Catálogos ni la edición de Personal
-- para este rol (ver home_screen.dart y app_state.dart).

-- ---------- Catálogos: unidades, sectores, cargos, turnos ----------
drop policy if exists "cls.catalogos_write" on public.unidades;
create policy "cls.catalogos_write" on public.unidades for all to authenticated
  using (es_admin())
  with check (es_admin());

drop policy if exists "cls.sectores_write" on public.sectores;
create policy "cls.sectores_write" on public.sectores for all to authenticated
  using (es_admin())
  with check (es_admin());

drop policy if exists "cls.cargos_write" on public.cargos;
create policy "cls.cargos_write" on public.cargos for all to authenticated
  using (es_admin())
  with check (es_admin());

drop policy if exists "cls.turnos_write" on public.turnos;
create policy "cls.turnos_write" on public.turnos for all to authenticated
  using (es_admin())
  with check (es_admin());

-- ---------- Personal ----------
drop policy if exists "per.personas_write_admin" on public.personas;
create policy "per.personas_write_admin" on public.personas for all to authenticated
  using (es_admin())
  with check (es_admin());

-- (per.personas_write_unidad sigue vigente para el jefe de unidad)

-- ---------- Vacaciones y libres ----------
drop policy if exists "aus.vacaciones_write_admin" on public.vacaciones;
create policy "aus.vacaciones_write_admin" on public.vacaciones for all to authenticated
  using (es_admin())
  with check (es_admin());

drop policy if exists "aus.libres_write_admin" on public.libres;
create policy "aus.libres_write_admin" on public.libres for all to authenticated
  using (es_admin())
  with check (es_admin());

-- (aus.*_write_unidad sigue vigente para jefe y rt de su unidad)

-- ---------- Perfiles y unidades a cargo ----------
drop policy if exists "perf.gestion_admin" on public.perfiles;
create policy "perf.gestion_admin" on public.perfiles for all to authenticated
  using (es_admin())
  with check (es_admin());

-- (perf.gestion_rt_unidad sigue vigente para el jefe de unidad)

drop policy if exists "dunidades.gestion" on public.perfil_unidades;
create policy "dunidades.gestion" on public.perfil_unidades for all to authenticated
  using (es_admin())
  with check (es_admin());

-- plan_mensual ya era solo admin/jefe: sin cambios.
