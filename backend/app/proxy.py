"""Proxy transparente hacia Supabase (PostgREST y GoTrue).

La app móvil apunta su URL de Supabase a este backend
(Supabase.initialize(url: <este servidor>)). De esta forma el teléfono solo
necesita resolver el host de Render, no el de Supabase; el backend, que sí
tiene DNS sano, reenvía cada llamada a su destino real con las claves tal cual
las mandó la app (anon key y/o JWT del usuario autenticado).
"""

from __future__ import annotations

import requests
from fastapi import Request
from fastapi.responses import JSONResponse, Response

from . import config

_BASE = config.SUPABASE_URL
_CLAVES_PROYECTO = {
    k for k in (config.SUPABASE_SERVICE_ROLE_KEY, config.SUPABASE_ANON_KEY) if k
}
_ENCAMBEZADOS_PASANTES = {"content-type", "content-range", "prefer", "retry-after"}


async def reenviar(servicio: str, path: str, request: Request) -> Response:
    """Reenvía /<servicio>/v1/... a Supabase y devuelve la respuesta tal cual."""
    target = f"{_BASE}/{servicio}/{path}"
    qs = request.url.query
    if qs:
        target += f"?{qs}"

    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in {"host", "content-length", "connection"}
    }

    # Nunca reenviar la service-role key (quedó configurada por accidente en un
    # cliente). Las claves anon y los JWT de sesión sí se reenvían tal cual.
    for valor in headers.values():
        if valor and valor in _CLAVES_PROYECTO and valor != config.SUPABASE_ANON_KEY:
            return JSONResponse(status_code=403, content={"error": "clave no permitida"})

    body: bytes | None = None
    if request.method not in {"GET", "HEAD", "OPTIONS"}:
        body = await request.body()

    try:
        r = requests.request(request.method, target, headers=headers, data=body, timeout=60)
    except requests.RequestException as exc:
        return JSONResponse(
            status_code=502,
            content={"error": "no se pudo contactar a Supabase", "detalle": str(exc)},
        )

    pasantes = {
        k: v
        for k, v in r.headers.items()
        if k.lower() in _ENCAMBEZADOS_PASANTES
    }
    return Response(content=r.content, status_code=r.status_code, headers=pasantes)