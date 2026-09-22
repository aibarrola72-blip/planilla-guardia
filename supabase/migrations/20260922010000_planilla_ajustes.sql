-- ============================================================
-- INERAM - Ajustes de planilla
-- 1) Turno noche con fecha de inicio (ancla por persona)
-- 2) Sectores claros: RAC, INTERNADOS; SALA V sin sector
-- ============================================================

alter table public.personas
  add column noche_desde date,
  add column noche_inicio_linea text
    check (noche_inicio_linea in ('N1','N2','N3'));

-- Derivar ancla nocturna desde el plan histórico
-- (primera celda nocturna de cada persona en plan_mensual)
with noct as (
  select distinct on (pm.persona_id)
         pm.persona_id,
         pm.fecha as noche_desde,
         t.codigo as noche_inicio_linea
  from public.plan_mensual pm
  join public.turnos t on t.id = pm.turno_id
  where t.codigo in ('N1','N2','N3')
  order by pm.persona_id, pm.fecha
)
update public.personas p
set noche_desde = n.noche_desde,
    noche_inicio_linea = n.noche_inicio_linea
from noct n
where p.id = n.persona_id;

-- Anclas referenciales conocidas (sobreescriben la derivación del plan)
update public.personas
set noche_desde = '2017-12-30', noche_inicio_linea = 'N1'
where nombre = 'Lic. Elida Gimenez';

update public.personas
set noche_desde = '2017-12-31', noche_inicio_linea = 'N2'
where nombre = 'Lic. Luz Alcaraz';

update public.personas
set noche_desde = '2018-01-01', noche_inicio_linea = 'N3'
where nombre = 'Lic. Esmilce Ortiz';

-- SALA V sin sector: se quita el sector 'SALA' y su personal queda sin sector
update public.personas
set sector_id = null
where sector_id in (select id from public.sectores where nombre = 'SALA');

delete from public.sectores where nombre = 'SALA';