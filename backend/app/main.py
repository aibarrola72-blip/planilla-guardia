"""API de reportes y administración - INERAM.

La app móvil llama a /api/reporte/mensual (con sesión) para obtener el HTML
o PDF de la planilla mensual. El admin opera desde el panel web /admin
(gestiona usuarios y catálogos).
"""

from __future__ import annotations

import calendar
import pathlib

from datetime import datetime

import requests
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

from . import config, database, proxy, reporte, seguridad

app = FastAPI(
    title="Reportes INERAM",
    description="Planilla de guardia mensual de enfermería + panel admin",
    version="0.2.0",
)

_ADMIN_HTML = pathlib.Path(config.TEMPLATES_DIR, "admin", "index.html")

ROLES_GESTION = {"admin", "jefe_enfermeria"}
ROLES_REPORTE = {"admin", "jefe_enfermeria", "jefe"}


class ReporteRequest(BaseModel):
    anio: int = Field(ge=2000, le=2100)
    mes: int = Field(ge=1, le=12)
    unidad_ids: list[int] = Field(default_factory=list)
    sector_ids: list[int] = Field(default_factory=list)
    formato: str = Field(default="html", pattern="^(html|pdf)$")


class UsuarioRequest(BaseModel):
    email: str = Field(min_length=3)
    rol: str | None = None
    unidad_id: int | None = None
    unidades: list[int] | None = None
    persona_id: int | None = None


class UsuarioPatch(BaseModel):
    rol: str | None = None
    unidad_id: int | None = None
    unidades: list[int] | None = None
    persona_id: int | None = None
    activo: bool | None = None


class FirmaPatch(BaseModel):
    subtitulo: str | None = None
    cargo_id: int | None = None
    persona_id: int | None = None
    nombre_fijo: str | None = None
    activo: bool | None = None


@app.get("/health")
def health():
    return {"status": "ok", "servicio": "reportes-ineram"}


@app.get("/")
def raiz():
    return {
        "servicio": "reportes-ineram",
        "endpoints": ["/api/reporte/mensual", "/reporte", "/admin"],
    }


@app.get("/api/config")
def config_app():
    """Configuración pública para el panel web (la anon key es pública)."""
    return {
        "supabaseUrl": config.SUPABASE_URL,
        "anonKey": config.SUPABASE_ANON_KEY,
        "roles": list(config.ROLES_VALIDOS),
    }


# ---------------------------------------------------------------
# Proxy hacia Supabase: la app apunta aquí su URL de Supabase para no
# depender del DNS del proyecto (el teléfono solo resuelve este servidor).
# ---------------------------------------------------------------
for _servicio in ("rest", "auth", "storage"):

    @app.api_route(
        f"/{_servicio}/{{path:path}}",
        methods=["GET", "POST", "PATCH", "PUT", "DELETE", "HEAD", "OPTIONS"],
        include_in_schema=False,
    )
    async def _supabase_proxy(path: str, request: Request, servicio: str = _servicio):
        return await proxy.reenviar(servicio, path, request)


# ---------------------------------------------------------------
# Invitación / creación de usuarios (web admin + jefe → RT)
# ---------------------------------------------------------------
def _buscar_usuario_por_email(email: str) -> dict | None:
    """Devuelve el usuario de Supabase Auth con ese email (o None)."""
    try:
        resp = requests.get(
            f"{config.SUPABASE_URL}/auth/v1/admin/users",
            headers={
                "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
                "Authorization": f"Bearer {config.SUPABASE_SERVICE_ROLE_KEY}",
            },
            params={"page": 1, "per_page": 1000},
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail="No se pudieron listar usuarios") from exc
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="No se pudieron listar usuarios")
    for u in resp.json().get("users", []):
        if u.get("email") == email:
            return u
    return None


def _crear_o_actualizar_usuario(
    email: str, rol: str | None, unidad_id: int | None, perfil: dict,
    unidades: list[int] | None = None, persona_id: int | None = None,
) -> dict:
    """Invita (o reenvía enlace a) un usuario y ajusta rol/unidad/persona/activo.

    Aplica las reglas de alcance por el rol del solicitante:
    - jefe: solo puede crear RT de sus unidades. Si aporta persona_id, el RT
      queda vinculado a esa persona (unidad + turno de la planilla).
    - admin / jefe_enfermeria: cualquier rol/unidad (una o varias).
    """
    rol_nuevo = rol or "rt"

    persona = None
    if persona_id:
        if rol_nuevo != "rt":
            persona_id = None  # el vínculo persona solo aplica a responsables de turno
        else:
            persona = database.obtener_persona(persona_id)
            if persona is None:
                raise HTTPException(status_code=400, detail="Persona no encontrada")

    if perfil["rol"] == "jefe":
        if rol_nuevo != "rt":
            raise HTTPException(status_code=403, detail="Un jefe de unidad solo puede invitar RT")
        mis_unidades = list(perfil.get("unidades") or [])
        if not mis_unidades:
            raise HTTPException(status_code=403, detail="Su perfil no tiene unidades asignadas")
        if persona:
            if persona["unidad_id"] not in mis_unidades:
                raise HTTPException(status_code=403, detail="La persona no pertenece a sus unidades")
            unidad_destino = persona["unidad_id"]
            unidades = [unidad_destino]
        else:
            if unidad_id not in (mis_unidades[0], None):
                raise HTTPException(status_code=403, detail="Solo puede invitar RT de sus unidades")
            unidad_destino = unidad_id or mis_unidades[0]
            unidades = [unidad_destino]
    else:
        # admin / jefe_enfermeria
        if rol_nuevo not in config.ROLES_VALIDOS:
            raise HTTPException(status_code=400, detail="Rol inválido")
        if persona:
            unidad_destino = persona["unidad_id"]
            unidades = [unidad_destino]
        else:
            if rol_nuevo == "rt" and not unidades and unidad_id is None:
                raise HTTPException(status_code=400, detail="Un RT necesita unidad asignada")
            if unidades:
                unidad_destino = unidades[0]
            else:
                unidad_destino = unidad_id

    existente = _buscar_usuario_por_email(email)
    if existente is None:
        # Usuario nuevo: generate_link crea el usuario pendiente y envía la invitación.
        seguridad.generar_invitacion(email)
        existente = _buscar_usuario_por_email(email)
    else:
        # Usuario ya registrado: reenviamos enlace para definir contraseña.
        seguridad.enviar_recuperacion(email)

    user_id = existente["id"] if existente else None
    if user_id:
        filas = database.obtener_perfil(user_id)
        if filas:
            campos: dict = {"rol": rol_nuevo, "activo": True, "unidad_id": unidad_destino}
            if persona_id:
                campos["persona_id"] = persona_id
            database.actualizar_perfil(user_id, campos)
            database.reemplazar_unidades(user_id, unidades or [])

    return {"email": email, "rol": rol_nuevo, "unidad_id": unidad_destino, "unidades": unidades, "persona_id": persona_id}


@app.post("/api/invitar")
def invitar(body: UsuarioRequest, request: Request):
    """Invita a un nuevo usuario con rol/unidad/persona (app móvil: jefe → RT)."""
    info = seguridad.requerir_perfil(request, ROLES_GESTION | {"jefe"})
    resultado = _crear_o_actualizar_usuario(body.email, body.rol, body.unidad_id, info["perfil"], body.unidades, body.persona_id)
    return {"ok": True, **resultado}


@app.get("/api/usuarios")
def listar_usuarios(request: Request):
    """Lista usuarios+perfiles. Admin/enfermeria: todos. Jefe: RTs de su unidad."""
    info = seguridad.requerir_perfil(request, ROLES_GESTION | {"jefe"})
    perfiles = database.listar_perfiles()
    try:
        resp = requests.get(
            f"{config.SUPABASE_URL}/auth/v1/admin/users",
            headers={
                "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
                "Authorization": f"Bearer {config.SUPABASE_SERVICE_ROLE_KEY}",
            },
            params={"page": 1, "per_page": 1000},
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail="No se pudieron listar usuarios") from exc
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="No se pudieron listar usuarios")

    emails = {u["id"]: u.get("email") for u in resp.json().get("users", [])}
    filas = []
    mis_unidades = set(info["perfil"].get("unidades") or [])
    for p in perfiles:
        uid = p["user_id"]
        if info["perfil"]["rol"] == "jefe":
            if p.get("rol") != "rt" or p.get("unidad_id") not in mis_unidades:
                continue
        filas.append({
            "user_id": uid,
            "email": emails.get(uid, ""),
            "rol": p.get("rol"),
            "unidad_id": p.get("unidad_id"),
            "unidades": p.get("unidades") or [],
            "persona_id": p.get("persona_id"),
            "activo": p.get("activo"),
        })
    return {"usuarios": filas}


@app.post("/api/usuarios")
def crear_usuario(body: UsuarioRequest, request: Request):
    """Crea + invita un usuario (web admin / jefe → RT)."""
    info = seguridad.requerir_perfil(request, ROLES_GESTION | {"jefe"})
    resultado = _crear_o_actualizar_usuario(body.email, body.rol, body.unidad_id, info["perfil"], body.unidades)
    return {"ok": True, **resultado}


@app.patch("/api/usuarios/{user_id}")
def actualizar_usuario(user_id: str, body: UsuarioPatch, request: Request):
    """Cambia rol/unidad/persona/activo. Jefe: solo RT de sus unidades."""
    info = seguridad.requerir_perfil(request, ROLES_GESTION | {"jefe"})
    filas = database.obtener_perfil(user_id)
    if not filas:
        raise HTTPException(status_code=404, detail="Usuario sin perfil")

    destino = filas[0]
    mis_unidades = set(info["perfil"].get("unidades") or [])
    if info["perfil"]["rol"] == "jefe":
        if destino.get("rol") != "rt" or destino.get("unidad_id") not in mis_unidades:
            raise HTTPException(status_code=403, detail="Solo puede modificar RT de su unidad")
        if body.rol not in (None, "rt"):
            raise HTTPException(status_code=403, detail="Un jefe solo puede gestionar RT")
        if body.unidad_id not in (None, *mis_unidades):
            raise HTTPException(status_code=403, detail="Solo puede operar sobre sus unidades")
        if body.unidades is not None:
            raise HTTPException(status_code=403, detail="Un jefe no puede asignar unidades")
        if body.persona_id is not None and body.persona_id != destino.get("persona_id"):
            persona = database.obtener_persona(body.persona_id)
            if persona is None or persona["unidad_id"] not in mis_unidades:
                raise HTTPException(status_code=403, detail="La persona no pertenece a sus unidades")

    if body.unidades is not None:
        database.reemplazar_unidades(user_id, body.unidades)
        body.unidad_id = body.unidades[0] if body.unidades else None

    if body.persona_id is not None and body.persona_id != destino.get("persona_id"):
        persona = database.obtener_persona(body.persona_id)
        if persona is None:
            raise HTTPException(status_code=400, detail="Persona no encontrada")
        database.reemplazar_unidades(user_id, [persona["unidad_id"]])
        body.unidad_id = persona["unidad_id"]

    campos: dict = {
        k: v for k, v in body.model_dump(exclude_unset=True).items() if k != "unidades"
    }
    if not campos:
        return {"ok": True}
    if "unidad_id" in campos and body.unidades is None and body.persona_id is None:
        uid = campos["unidad_id"]
        database.reemplazar_unidades(user_id, [uid] if uid else [])
    database.actualizar_perfil(user_id, campos)
    return {"ok": True}


# ---------------------------------------------------------------
# Firmas de la planilla (panel admin)
# ---------------------------------------------------------------
@app.get("/api/firmas")
def listar_firmas(request: Request):
    """Config de firmas + catálogos para el selector del panel."""
    seguridad.requerir_perfil(request, ROLES_GESTION)
    return {
        "firmas": database.obtener_firmas(),
        "cargos": database.obtener_cargos(),
        "personas": database.obtener_personal_listado(),
    }


@app.patch("/api/firmas/{clave}")
def actualizar_firma(clave: str, body: FirmaPatch, request: Request):
    """Actualiza una firma (subtitulo, cargo, persona o nombre fijo)."""
    seguridad.requerir_perfil(request, ROLES_GESTION)
    los_clave = {f["clave"] for f in database.obtener_firmas()}
    if clave not in los_clave:
        raise HTTPException(status_code=404, detail="Firma inexistente")
    campos = body.model_dump(exclude_unset=True)
    database.actualizar_firma(clave, campos)
    return {"ok": True}


# ---------------------------------------------------------------
# Panel de administración (web)
# ---------------------------------------------------------------
@app.get("/admin")
def panel_admin():
    """Panel web del admin: gestión de usuarios y catálogos."""
    if not _ADMIN_HTML.exists():
        raise HTTPException(status_code=404, detail="Panel no disponible")
    return HTMLResponse(_ADMIN_HTML.read_text(encoding="utf-8"))


# ---------------------------------------------------------------
# Reporte mensual
# ---------------------------------------------------------------
def _generar(
    anio: int,
    mes: int,
    unidad_ids: list[int],
    sector_ids: list[int],
    formato: str,
) -> tuple[str | bytes, str, str]:
    def _leer() -> dict:
        _, total = calendar.monthrange(anio, mes)
        desde = datetime(anio, mes, 1).date().isoformat()
        hasta = datetime(anio, mes, total).date().isoformat()
        return {
            "unidades": database.obtener_unidades(),
            "sectores": database.obtener_sectores(),
            "turnos": database.obtener_turnos(),
            "personas": database.obtener_personas(list(unidad_ids), list(sector_ids)),
            "personas_todas": database.obtener_personas([], []),
            "firmas": database.obtener_firmas(),
            "vacaciones": database.obtener_vacaciones_descargadas(desde, hasta),
            "libres": database.obtener_libres_descargados(desde, hasta),
            "plan": database.obtener_plan_para(desde, hasta),
        }

    try:
        datos = _leer()
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Error leyendo datos") from exc

    try:
        return reporte.generar_reporte(
            anio=anio,
            mes=mes,
            datos=datos,
            unidad_ids=unidad_ids,
            sector_ids=sector_ids,
            formato=formato,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Error generando el reporte") from exc


@app.post("/api/reporte/mensual")
def reporte_mensual(body: ReporteRequest, request: Request):
    seguridad.requerir_perfil(request, ROLES_REPORTE)
    contenido, media_type, unidad_nombre = _generar(
        anio=body.anio,
        mes=body.mes,
        unidad_ids=body.unidad_ids,
        sector_ids=body.sector_ids,
        formato=body.formato,
    )

    if isinstance(contenido, str):
        return HTMLResponse(content=contenido)
    nombre = reporte.nombre_archivo_pdf(unidad_nombre, body.anio, body.mes)
    return Response(
        content=contenido,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{nombre}"'},
    )


@app.get("/reporte")
def reporte_web(
    anio: int,
    mes: int,
    request: Request,
    formato: str = "html",
    unidad_ids: str = "",
    sector_ids: str = "",
):
    """Vista web de la planilla: /reporte?anio=2026&mes=9 (requiere sesión)."""
    seguridad.requerir_perfil(request, ROLES_REPORTE)

    def _desde_csv(value: str) -> list[int]:
        return [int(x) for x in value.split(",") if x.strip()]

    contenido, media_type, unidad_nombre = _generar(
        anio=anio,
        mes=mes,
        unidad_ids=_desde_csv(unidad_ids),
        sector_ids=_desde_csv(sector_ids),
        formato=formato,
    )

    if isinstance(contenido, str):
        return HTMLResponse(content=contenido)
    nombre = reporte.nombre_archivo_pdf(unidad_nombre, anio, mes)
    return Response(
        content=contenido,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{nombre}"'},
    )