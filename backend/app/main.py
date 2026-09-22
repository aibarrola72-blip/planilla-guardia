"""API de reportes de guardia - INERAM.

La app móvil llama a /api/reporte/mensual para obtener el HTML o PDF
de la planilla mensual de guardia.
"""

from __future__ import annotations

import calendar
from datetime import datetime

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

from . import config, database, reporte

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