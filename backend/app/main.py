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
    return {"servicio": "reportes-ineram", "endpoints": ["/api/reporte/mensual"]}


@app.post("/api/reporte/mensual")
def reporte_mensual(body: ReporteRequest):
    try:
        unidad_ids = list(body.unidad_ids)
        sector_ids = list(body.sector_ids)

        # Todo el plan del mes solicitado
        _, total = calendar.monthrange(body.anio, body.mes)
        desde = datetime(body.anio, body.mes, 1).date().isoformat()
        hasta = datetime(body.anio, body.mes, total).date().isoformat()

        datos = {
            "unidades": database.obtener_unidades(),
            "sectores": database.obtener_sectores(),
            "turnos": database.obtener_turnos(),
            "personas": database.obtener_personas(unidad_ids, sector_ids),
            "vacaciones": database.obtener_vacaciones_descargadas(),
            "libres": database.obtener_libres_descargados(),
            "plan": database.obtener_plan_para(desde, hasta),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Error leyendo datos: {exc}") from exc

    try:
        contenido, media_type = reporte.generar_reporte(
            anio=body.anio,
            mes=body.mes,
            datos=datos,
            unidad_ids=unidad_ids,
            sector_ids=sector_ids,
            formato=body.formato,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Error generando reporte: {exc}") from exc

    if isinstance(contenido, str):
        return HTMLResponse(content=contenido)
    nombre = (
        f"planilla_guardia_{body.anio}_{body.mes:02d}.pdf"
    )
    return Response(
        content=contenido,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{nombre}"'},
    )