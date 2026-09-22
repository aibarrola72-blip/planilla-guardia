-- ============================================================
-- INERAM - Orden de la planilla por turno y numeración única
-- Renumera 1..n a las personas ACTIVAS en el orden de la planilla:
-- grupos M, T, N1-3, D y dentro de cada grupo por unidad, orden y nombre.
-- ============================================================

with ordenados as (
  select p.id,
         row_number() over (
           order by
             case t.codigo
               when 'M'  then 0
               when 'T'  then 1
               when 'N1' then 2
               when 'N2' then 3
               when 'N3' then 4
               when 'D'  then 5
               else 6
             end,
             p.unidad_id nulls first,
             p.orden,
             p.nombre
         ) as num
  from public.personas p
  left join public.turnos t on t.id = p.turno_id
  where p.estado = 'ACTIVO'
)
update public.personas p
set orden = o.num
from ordenados o
where p.id = o.id
  and p.orden is distinct from o.num;