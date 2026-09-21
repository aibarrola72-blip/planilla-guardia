# Arquitectura — Planilla de Guardia de Enfermería (INERAM)

Documento de referencia del sistema de planilla de guardia para el jefe de
unidad, que permite generar el reporte mensual desde una aplicación móvil.

## Objetivo

Digitalizar el control de **libres**, **vacaciones** y **turnos** del personal
de enfermería, reemplazando el flujo actual basado en Google Sheets + script
Python, y generar el mismo reporte imprimible (landscape, logos, firmas) desde
una app móvil, conservando todo el histórico existente.

## Stack

| Capa               | Tecnología                                              |
| ------------------ | ------------------------------------------------------- |
| App móvil          | Flutter (`app/`)                                         |
| Backend + BD + Auth| Supabase: PostgreSQL + PostgREST + Auth (RLS)           |
| Servicio reportes  | FastAPI (`backend/`) — reutiliza `generar_reporte.py`   |
| PDF                | HTML (Jinja2) → WeasyPrint                              |
| Despliegue         | Supabase Cloud + FastAPI en Render/Railway              |
| Migración          | `migracion/importar_sheets.py` (Google Sheets → Supabase)|

```
┌─────────────┐   anon key + sesión   ┌──────────────┐  PostgREST  ┌──────────────┐
│ App Flutter  │ ────────────────────▶ │   Supabase    │ ──────────▶ │ PostgreSQL    │
│ (jefe unidad)│                       │  Auth + API   │             │  (datos)      │
└──────┬──────┘                       └──────┬───────┘             └──────┬───────┘
       │  POST /api/reporte/mensual         │  service-role (solo servidor)│
       └──────────────────────────────────▶ FastAPI (reportes HTML/PDF)    │
```

## Modelo de datos (Supabase PostgreSQL)

```
unidades    (id, nombre, activo)                    ← URGENCIAS, SALA V (CRUD)
sectores    (id, unidad_id, nombre, activo)         ← RAC, INTERNADOS, SALA (CRUD)
cargos      (id, nombre, activo)                    ← RT, JEFATURA, AUXILIAR… (CRUD)
turnos      (id, codigo M/T/N1/N2/N3/D, descripcion, hora_inicio, hora_fin)
personas    (id, idpersonal_legacy, nombre, ci, registro, unidad_id, sector_id,
             cargo_id, turno_id, estado ACTIVO/INACTIVO, orden)
vacaciones  (id, persona_id, fecha_inicio, fecha_fin, observacion)   → rangos
libres      (id, persona_id, fecha_inicio, fecha_fin, motivo)        → rangos
plan_mensual(persona_id, fecha, turno_id)            → celda por día (upsert persona+fecha)
perfiles    (user_id, rol)                           → rol 'jefe'
```

Seguridad: **RLS** en todas las tablas; solo usuarios autenticados con rol
`jefe` operan. La **service-role key** vive únicamente en el servidor de
reportes (nunca en la app).

## Reglas funcionales

### Turnos y horarios
| Código | Turno          | Horario          |
| ------ | -------------- | ---------------- |
| M      | Mañana         | 06:00 – 12:00    |
| T      | Tarde          | 12:00 – 18:00    |
| N1/N2/N3 | Noche (líneas) | 18:00 – 06:00 |
| D      | Fin de semana (sáb+dom) | 06:00 – 18:00 |

### Orden del personal
- `personas.orden` define la **posición en la planilla impresa**, por grupo
  `unidad + sector`. Se reordena en el módulo Personal (flechas/drag).
- Los **inactivos** se conservan en BD, quedan ocultos en la app por defecto
  y nunca aparecen en la planilla.
- Cambio de turno/cargo por persona disponible en el módulo Personal.

### Reporte — prioridad por celda
1. **Vacaciones** → celda combinada `VACACIONES DESDE … HASTA …`
2. **Libres** → `L`
3. **Turno** del plan (M/T/N1/N2/N3/D), o vacío

### Planificación
- Las asignaciones se administran para el **mes a planificar** (y futuros).
- **Autocompletar** genera la base desde el `turno_id` de cada persona:
  M/T → lunes–viernes; D → sábado+domingo; N1/N2/N3 → rotación nocturna.
- Meses anteriores: **solo lectura**.
- El plan se guarda en `plan_mensual` (upsert por persona+fecha).

## Migración (no se pierde nada)

| Fuente (Google Sheets)      | Destino              | Registros (aprox.) |
| --------------------------- | -------------------- | ------------------ |
| `NOMINA`                    | `personas` + catálogos | 47                |
| `ASIGNACION VACACIONES`     | `vacaciones`          | 109                |
| `ASIGNACION LIBRES`         | `libres` (rangos)     | 1390 → ~N rangos   |
| `LISTADO PERSONAL Y TURNOS` | `plan_mensual`        | mes actual         |
| `UNIDAD`, `TURNO`           | catálogos             | —                  |
| `PLANILLA`, `REPORTE IMPRESION`, `REPORTES` | regeneradas / archivo | — |

La clave de referencia histórica es `idpersonal_legacy` (id de AppSheet);
vacaciones/libres se cruzan por CI normalizado.

## Estructura del repositorio

```
Reportes - INERAM/
  supabase/001_schema.sql      # esquema + RLS + seed
  backend/                     # FastAPI (reportes HTML/PDF)
    app/                       #   config, database (PostgREST), reporte, main
    templates/reporte.html     #   plantilla impresa (Jinja2)
    assets/                    #   logos
  app/                         # Flutter
    lib/
      config.dart              #   URLs (Supabase + backend de reportes)
      models/                  #   Unidad, Sector, Cargo, Turno, Persona,…
      services/supabase_service.dart
      state/app_state.dart     #   sesión
      screens/                 #   login, home, personal, catálogos,
                               #   vacaciones/libres, plan del mes, reporte
  migracion/importar_sheets.py # import desde Google Sheets
```

## API (backend de reportes)

- `GET /health`
- `POST /api/reporte/mensual`
  Body: `{ anio, mes, unidad_ids, sector_ids, formato: "html"|"pdf" }`
  → HTML imprimible o PDF (landscape, logos y firmas).

## Flujo de trabajo del jefe

1. **Login** (Supabase Auth).
2. **Catálogos**: crear/ajustar unidades, sectores y cargos.
3. **Personal**: alta/baja, reordenar, cambiar turno/cargo; inactivos ocultos.
4. **Vacaciones y Libres**: cargar rangos por persona (se pintan sobre el mes).
5. **Plan del mes**: autocompletar + ajustes celda a celda.
6. **Reporte**: elegir mes/unidad/sector → generar PDF → compartir/imprimir.

## Fases de implementación

| Fase | Contenido | Estado |
| ---- | --------- | ------ |
| 0    | Esquema SQL + RLS + seed; backend FastAPI; proyecto Flutter base | ✅ Hecho |
| 1    | Login + Personal + Catálogos (funcional en la app base)          | ✅ Hecho |
| 2    | Vacaciones y Libres (rangos)                                      | ✅ Hecho |
| 3    | Plan del mes: grid editable + autocompletar                       | ✅ Hecho |
| 4    | Reporte: PDF via backend + compartir desde la app                 | ✅ Hecho |
| 5    | Aplicar migración real, pruebas E2E y despliegue                  | ⏳ Pendiente |

## Notas de puesta en producción

1. Crear el proyecto Supabase y ejecutar `supabase/001_schema.sql`.
2. Configurar `app/lib/config.dart` (URL + anon key) y generar el APK.
3. Desplegar `backend/` (Dockerfile) con las variables necesarias
   (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`).
4. Configurar `AppConfig.apiReportesUrl` en la app apuntando al backend.
5. Ejecutar `migracion/importar_sheets.py` para poblar los datos históricos.