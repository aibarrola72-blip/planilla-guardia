"""API de reportes de guardia - INERAM.

La app móvil llama a /api/reporte/mensual para obtener el HTML o PDF
de la planilla mensual de guardia.
"""

from __future__ import annotations

import calendar
from datetime import datetime

import requests
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

from . import config, database, proxy, reporte

app = FastAPI(
    title="Reportes INERAM",
    description="Generación de la planilla de guardia mensual de enfermería",
    version="0.1.0",
)


class ReporteRequest(BaseModel):
    anio: int = Field(ge=2000, le=2100)
    mes: int = Field(ge=1, le=12)
    unidad_ids: list[int] = Field(default_factory=list)
    sector_ids: list[int] = Field(default_factory=list)
    formato: str = Field(default="html", pattern="^(html|pdf)$")


@app.get("/health")
def health():
    return {"status": "ok", "servicio": "reportes-ineram"}


@app.get("/")
def raiz():
    return {"servicio": "reportes-ineram", "endpoints": ["/api/reporte/mensual", "/reporte"]}


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
# Invitación de jefe: genera la invitación de Supabase con redirect hacia
# la app (ineramapp://...) para que el correo abra la app, no una página
# inválida de Supabase.
# ---------------------------------------------------------------
class InvitarRequest(BaseModel):
    email: str = Field(min_length=3)


@app.post("/api/invitar")
def invitar_jefe(body: InvitarRequest, request: Request):
    cabecera = request.headers.get("Authorization", "")
    if not cabecera.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Sesión requerida")
    token = cabecera[7:]

    # Validar el JWT del jefe contra GoTrue antes de invitaciones.
    try:
        resp_usuario = requests.get(
            f"{config.SUPABASE_URL}/auth/v1/user",
            headers={"apikey": config.SUPABASE_ANON_KEY, "Authorization": f"Bearer {token}"},
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"No se pudo validar la sesión: {exc}") from exc
    if resp_usuario.status_code != 200:
        raise HTTPException(status_code=401, detail="Sesión inválida o expirada")

    try:
        resp = requests.post(
            f"{config.SUPABASE_URL}/auth/v1/admin/generate_link",
            headers={
                "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
                "Authorization": f"Bearer {config.SUPABASE_SERVICE_ROLE_KEY}",
            },
            json={
                "type": "invite",
                "email": body.email,
                "options": {"redirect_to": config.AUTH_REDIRECT_URL},
            },
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"No se pudo contactar Supabase: {exc}") from exc
    if resp.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Supabase respondió {resp.status_code}: {resp.text[:200]}",
        )
    return {"ok": True, "email": body.email}


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
            "vacaciones": database.obtener_vacaciones_descargadas(desde, hasta),
            "libres": database.obtener_libres_descargados(desde, hasta),
            "plan": database.obtener_plan_para(desde, hasta),
        }

    try:
        datos = _leer()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Error leyendo datos: {exc}") from exc

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
        raise HTTPException(status_code=500, detail=f"Error generando reporte: {exc}") from exc


@app.post("/api/reporte/mensual")
def reporte_mensual(body: ReporteRequest):
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
    formato: str = "html",
    unidad_ids: str = "",
    sector_ids: str = "",
):
    """Vista web de la planilla: /reporte?anio=2026&mes=9"""
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