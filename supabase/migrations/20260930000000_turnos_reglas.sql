-- Reglas de asignación y orden de turnos como DATOS (no como literales en código).
-- Permite crear turnos nuevos (ej. M1, N4, T2) desde el catálogo sin tocar la app
-- ni el backend.
--
--   regla           LABORABLE   -> se asigna de lunes a viernes
--                   FIN_SEMANA  -> se asigna sábado y domingo
--                   NOCTURNA    -> rotación de 3 días anclada en personas.noche_desde
--                   OTRO        -> no se autocompleta (se asigna manualmente)
--   rotacion_offset 0|1|2       -> posición inicial dentro de la rotación nocturna
--   orden_grupo     smallint    -> orden en la planilla (app y PDF)
--
-- Los defaults reproducen el comportamiento previo al cambio, por lo que clientes
-- desactualizados (APK viejos, backend viejo) siguen operando sin romperse.

alter table public.turnos
  add column regla           text        not null default 'OTRO',
  add column rotacion_offset smallint,
  add column orden_grupo     smallint    not null default 99;

comment on column public.turnos.regla is
  'LABORABLE | FIN_SEMANA | NOCTURNA | OTRO. Regla de autocompletado del plan mensual.';
comment on column public.turnos.rotacion_offset is
  'Offset 0..2 de la rotación nocturna; solo aplica cuando regla = NOCTURNA.';
comment on column public.turnos.orden_grupo is
  'Orden de aparición en la planilla (app y PDF). Menor = primero.';

-- Backfill de los turnos existentes (equivalente al switch anterior en la app).
update public.turnos set regla = 'LABORABLE',  orden_grupo = 0 where codigo in ('M', 'M1');
update public.turnos set regla = 'LABORABLE',  orden_grupo = 1 where codigo = 'T';
update public.turnos set regla = 'FIN_SEMANA', orden_grupo = 5 where codigo = 'D';
update public.turnos
   set regla = 'NOCTURNA',
       orden_grupo = 2,
       rotacion_offset = case codigo when 'N1' then 0 when 'N2' then 1 when 'N3' then 2 end
 where codigo in ('N1', 'N2', 'N3');
