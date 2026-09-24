# Runbook de producción — INERAM (versión con roles)

Código: rama `prueba`, último commit `a793f06` (firmas dinámicas).
Producción (v1) congelada en `b79b426` / tag `prod-v1-2026-09-24`.

> **Regla de oro**: las migraciones de BD se aplican **antes** de desplegar el
> backend nuevo. Al aplicarlas, la app v1 instalada queda con el nuevo RLS
> (los jefes pasan a tener permisos acotados por rol/unidad) hasta que se
> instale la nueva APK, así que el salto debe hacerse en un momento
> acordado con el cliente (ej. fuera de horario de carga).

---

## 1. Migraciones pendientes en producción

Producción tiene solo 3 migraciones v1:
`20260921000000_init`, `20260922010000_planilla_ajustes`, `20260922020000_orden_por_turno`.

Faltan (ambas **aditivas**, re-ejecutables sin romper):
- `supabase/migrations/20260924010000_roles.sql` — modelo de roles
  (admin / jefe_enfermeria / jefe / rt) + RLS por rol/unidad + trigger
  nuevo usuario → `rt`. Compatible con prod: v1 usaba solo rol `'jefe'`,
  que sigue siendo válido (no falla el nuevo check).
- `supabase/migrations/20260924030000_firmas_planilla.sql` — firmas del
  reporte (tabla + seeds `on conflict do nothing` + RLS).

Aplicar (desde `/backend`, con venv activo; `SUPABASE_DB_CONNECTION` está
en `backend/.env`):

```powershell
$envVals = @{}; Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { $envVals[$matches[1].Trim()] = $matches[2].Trim() } }
$env:SUPABASE_DB_CONNECTION = $envVals['SUPABASE_DB_CONNECTION']

.venv\Scripts\python.exe ..\migracion\aplicar_sql.py ..\supabase\migrations\20260924010000_roles.sql
.venv\Scripts\python.exe ..\migracion\aplicar_sql.py ..\supabase\migrations\20260924030000_firmas_planilla.sql
```

Verificar:

```powershell
.venv\Scripts\python.exe ..\migracion\estado_db.py
.venv\Scripts\python.exe ..\migracion\verificar_migracion.py
```

Debería aparecer `firmas_planilla` entre las tablas y las versiones
`20260924010000` y `20260924030000` registradas.

---

## 2. Roles de usuarios existentes

Tras las migraciones **todos los usuarios actuales quedan `rol='jefe'`**
(antes `'jefe'`, el check lo permite). Hay que definir quién es cada cosa
con el cliente:

| Rol | Quién | Cómo asignar |
|-----|-------|--------------|
| `admin` | Persona que gestiona el sistema por web | `crear_admin.py` (paso 3) |
| `jefe_enfermeria` | Supervisor/a de Dpto. de Enfermería | SQL (abajo) |
| `jefe` | Jefe de cada unidad (sigue) | ya está (asignar `unidad_id`) |
| `rt` | Personal que solo carga libres/vacaciones | SQL o invitación del jefe |

Asignar `jefe_enfermeria` / `unidad_id` / `activo` por email
(solo lectura puntual, altera perfiles):

```sql
-- ejemplo: marcar a Laura como jefe_enfermeria, activa
update public.perfiles p set rol='jefe_enfermeria', activo=true, updated_at=now()
from auth.users u where p.user_id=u.id and u.email='laura@ineram';

-- ejemplo: asignar unidad a un jefe (id de unidades = los de producción)
update public.perfiles p set unidad_id=<id_unidad>
from auth.users u where p.user_id=u.id and u.email='jefe@ineram' and p.rol='jefe';
```

> Alternativa **sin SQL**: en cuanto esté desplegado el backend, el
> admin/jefe_enfermeria puede reasignar roles desde el panel web
> (pestaña Usuarios), que solo edita `perfiles` con permisos RLS válidos.

---

## 3. Crear el usuario admin inicial

```powershell
$envVals = @{}; Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#=]+)=(.*)$') { $envVals[$matches[1].Trim()] = $matches[2].Trim() } }
$env:SUPABASE_URL        = $envVals['SUPABASE_URL']
$env:SUPABASE_SERVICE_ROLE_KEY = $envVals['SUPABASE_SERVICE_ROLE_KEY']
$env:SUPABASE_DB_CONNECTION    = $envVals['SUPABASE_DB_CONNECTION']
$env:ADMIN_EMAIL         = "<email-admin@ineram>"
$env:ADMIN_PASSWORD      = "<cambiar>"   # si no se setea, solo reasigna rol

.venv\Scripts\python.exe ..\migracion\crear_admin.py
```

---

## 4. Desplegar el backend (Render) — sugerencia

El backend no tiene `render.yaml`/Procfile en el repo: el servicio de
Render se crea desde el tablero (raíz `backend`, comando
`uvicorn app.main:app --host 0.0.0.0 --port $PORT`), leyendo las
variables de `backend/.env`.

**Flujo recomendado (seguro, sin tocar producción antes de tiempo):**
1. Aplicar pasos 1–3 y validar con uvicorn local (ver sección 6).
2. Mergeir `prueba` → `main` y taggear `prod-v2-2026-09-24` (paso 7).
3. En Render: confirmar que el servicio **auto-deploya desde `main`**
   (o pulsar "Manual Deploy / Deploy latest commit").
4. Verificar salud y endpoints nuevos (sección 5).

> No desplegar el backend nuevo antes de aplicar las migraciones: para
> `firmas_planilla` inexistente el API responde 500.

---

## 5. Verificación del despliegue

```powershell
# health
Invoke-RestMethod -Uri https://<render-url>/health

# login admin
$tok = (Invoke-RestMethod -Uri https://<render-url>/auth/v1/token?grant_type=password `
  -Method Post -ContentType 'application/json' `
  -Body '{"email":"<admin@ineram>","password":"<cambiar>"}').access_token
$h = @{ Authorization = "Bearer $tok"; apikey = $env:SUPABASE_ANON_KEY }

# firmas + catálogos del selector
Invoke-RestMethod -Uri https://<render-url>/api/firmas -Headers $h

# reporte con firmas dinámicas (miramos el bloque <div class="firmas">)
$html = Invoke-WebRequest -Uri https://<render-url>/api/reporte/mensual -Method Post `
  -Headers $h -ContentType 'application/json' -Body '{"anio":2026,"mes":10,"formato":"html"}' -UseBasicParsing
```

Panel web de admin: `https://<render-url>/admin` → login del usuario `admin`,
pestañas **Usuarios** (roles), **Catálogos** (incluye Turnos) y **Firmas**
(cargo / persona / nombre fijo, activar/desactivar).

---

## 6. Prueba local equivalente (ya validado 2026-09-24)

Backend local en `http://127.0.0.1:8010` con:
`SUPABASE_URL=http://127.0.0.1:54321`,
`SUPABASE_SERVICE_ROLE_KEY` y `SUPABASE_ANON_KEY` locales.
Usuarios de prueba: `admin@ineram.test / Admin123!`.

Comprobado hoy:
- `GET /api/firmas` → 3 firmas sembradas + cargos + personal activo.
- `PATCH /api/firmas/{clave}` por **cargo** (lista todo el personal ACTIVO
  con ese cargo), por **persona**, y por **nombre fijo** — presentes en el
  bloque `.firmas` del HTML del reporte.
- `flutter analyze`: 0 errores, 0 warnings (solo 9 infos preexistentes).
- APK: `INERAM-Planilla_2026-09-24b.apk` (53.5 MB) ya generado.

---

## 7. Distribución y ramas

1. `git checkout main` (o `productivo`)
   `git merge prueba`  → tag `prod-v2-2026-09-24`
2. Distribuir `INERAM-Planilla_2026-09-24b.apk` (β/test) o subir a
   Play/legacy según flujo actual del cliente.
3. Al publicar, el alta de nuevos usuarios es **solo por invitación**:
   los RT se generan desde la app (botón "Invitar personal") y los
   perfiles quedan `rol='rt'` por trigger; el admin completa rol/unidad.

---

## 8. Rollback / notas

- Las migraciones 4 y 5 son **aditivas**: revertir requiere acciones
  manuales por servicios (`drop policy if exists`, `alter table` para
  quitar columnas nuevamente). No se contempla rollback automático.
- Estado previo restaurable: restaurando el backup de la BD v1
  (Snapshot en Supabase) y redeployando el backend v1 (commit `b79b426`).
- `backend/.env` contiene claves de **producción**: no usarlas en tests
  locales (el stack local de Supabase está en `127.0.0.1:54xxx`).