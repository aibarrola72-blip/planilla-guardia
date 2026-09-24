"""Acceso a datos de Supabase vía PostgREST (REST) con la service-role key.

La service-role key vive únicamente en el servidor (variables de entorno),
nunca en la app móvil.
"""

from __future__ import annotations

import requests

from . import config


def _headers() -> dict:
    return {
        "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {config.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _get(tabla: str, params: dict | None = None) -> list[dict]:
    url = f"{config.SUPABASE_URL}/rest/v1/{tabla}"
    resp = requests.get(url, headers=_headers(), params=params or {}, timeout=30)
    resp.raise_for_status()
    return resp.json()


def _post(tabla: str, body: dict, prefer: str = "return=representation") -> list[dict] | None:
    url = f"{config.SUPABASE_URL}/rest/v1/{tabla}"
    headers = _headers()
    headers["Prefer"] = prefer
    resp = requests.post(url, headers=headers, json=body, timeout=30)
    resp.raise_for_status()
    if resp.status_code == 201:
        return resp.json()
    return None


def _upsert(tabla: str, body: list[dict]) -> list[dict] | None:
    url = f"{config.SUPABASE_URL}/rest/v1/{tabla}"
    headers = _headers()
    headers["Prefer"] = "resolution=merge-duplicates,return=representation"
    resp = requests.post(url, headers=headers, json=body, timeout=60)
    resp.raise_for_status()
    return resp.json() if resp.status_code == 201 else None


def _query(tabla: str, **filtros) -> list[dict]:
    params = {}
    for clave, valor in filtros.items():
        if valor is None:
            continue
        if isinstance(valor, bool):
            params[clave] = "true" if valor else "false"
        elif isinstance(valor, (list, tuple)):
            for i, v in enumerate(valor):
                params[f"{clave}.eq.{v}"] = "true"
        else:
            params[clave] = f"eq.{valor}"
        break  # solo un filtro por este helper simple
    return _get(tabla, params)


def obtener_unidades() -> list[dict]:
    return _get("unidades", {"select": "id,nombre,activo", "activo": "eq.true"})

def obtener_sectores() -> list[dict]:
    return _get("sectores", {"select": "id,unidad_id,nombre,activo", "activo": "eq.true"})

def obtener_cargos() -> list[dict]:
    return _get("cargos", {"select": "id,nombre,activo", "activo": "eq.true"})

def obtener_turnos() -> list[dict]:
    return _get("turnos", {"select": "id,codigo,descripcion,hora_inicio,hora_fin,activo", "activo": "eq.true"})


def obtener_personas(unidad_ids: list[int], sector_ids: list[int], incluir_inactivos: bool = False) -> list[dict]:
    """Personal ACTIVO por unidad/sector, ordenado para la planilla."""
    params = {
        "select": "id,idpersonal_legacy,nombre,ci,registro,estado,orden,"
                  "unidad_id,sector_id,cargo_id,turno_id,"
                  "sector: sectores(nombre), cargo: cargos(nombre), turno: turnos(codigo)",
        "order": "unidad_id.nullsfirst,sector_id.nullsfirst,orden,nombre",
    }
    if not incluir_inactivos:
        params["estado"] = "eq.ACTIVO"
    if sector_ids:
        params["sector_id"] = "in.(" + ",".join(map(str, sector_ids)) + ")"
    elif unidad_ids:
        params["unidad_id"] = "in.(" + ",".join(map(str, unidad_ids)) + ")"
    return _get("personas", params)


def obtener_vacaciones_descargadas(fecha_desde: str, fecha_hasta: str) -> list[dict]:
    """Vacaciones que tocan el rango [desde, hasta] (evita el límite de 1000 filas)."""
    params = [
        ("select", "id,persona_id,fecha_inicio,fecha_fin,observacion"),
        ("fecha_inicio", f"lte.{fecha_hasta}"),
        ("fecha_fin", f"gte.{fecha_desde}"),
    ]
    return _get("vacaciones", params)

def obtener_libres_descargados(fecha_desde: str, fecha_hasta: str) -> list[dict]:
    """Libres que tocan el rango [desde, hasta] (evita el límite de 1000 filas)."""
    params = [
        ("select", "id,persona_id,fecha_inicio,fecha_fin,motivo"),
        ("fecha_inicio", f"lte.{fecha_hasta}"),
        ("fecha_fin", f"gte.{fecha_desde}"),
    ]
    return _get("libres", params)

def obtener_plan_para(fecha_desde: str, fecha_hasta: str) -> list[dict]:
    params = [
        ("select", "id,persona_id,fecha,turno_id,turno: turnos(codigo)"),
        ("fecha", f"gte.{fecha_desde}"),
        ("fecha", f"lte.{fecha_hasta}"),
    ]
    return _get("plan_mensual", params)


def guardar_plan_mensual(filas: list[dict]) -> list[dict] | None:
    """Upsert de celdas del plan mensual (persona_id, fecha, turno_id)."""
    return _upsert("plan_mensual", filas)


# ---------- perfiles (roles) ----------

def obtener_perfil(user_id: str) -> list[dict]:
    """Perfil del usuario. Usado por el backend (service-role) para RLS/autorización."""
    return _get("perfiles", {"select": "rol,unidad_id,activo", "user_id": f"eq.{user_id}"})


def listar_perfiles() -> list[dict]:
    """Todos los perfiles (para el panel admin)."""
    return _get("perfiles", {"select": "user_id,rol,unidad_id,activo,updated_at", "order": "updated_at.desc"})


def actualizar_perfil(user_id: str, campos: dict) -> None:
    """Actualiza rol/unidad/activo de un perfil (service-role, bypassea RLS)."""
    url = f"{config.SUPABASE_URL}/rest/v1/perfiles"
    headers = _headers()
    resp = requests.patch(url, headers=headers, json=campos, params={"user_id": f"eq.{user_id}"}, timeout=30)
    resp.raise_for_status()


# ---------- firmas de la planilla ----------

def obtener_firmas() -> list[dict]:
    """Config de firmas del reporte, con nombre de persona/cargo embebido."""
    return _get(
        "firmas_planilla",
        {
            "select": "clave,subtitulo,cargo_id,persona_id,nombre_fijo,orden,activo,"
                      "cargo: cargos(nombre), persona: personas(nombre)",
            "order": "orden.asc",
        },
    )


def obtener_personal_listado() -> list[dict]:
    """Personal completo para selects del panel (incluye inactivos)."""
    return _get("personas", {"select": "id,nombre,unidad_id,cargo_id,estado", "order": "nombre.asc"})


def actualizar_firma(clave: str, campos: dict) -> None:
    """Actualiza una firma por su clave (service-role, bypassea RLS)."""
    url = f"{config.SUPABASE_URL}/rest/v1/firmas_planilla"
    headers = _headers()
    resp = requests.patch(url, headers=headers, json=campos, params={"clave": f"eq.{clave}"}, timeout=30)
    resp.raise_for_status()