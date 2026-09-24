"""Seguridad: validación de sesión y control de roles para los endpoints.

Patrón usado: el token JWT del usuario se valida contra GoTrue
(/auth/v1/user). Luego se consulta su perfil (public.perfiles) vía
PostgREST con la service-role key, que vive solo en el servidor.

Los errores son genéricos: nunca se expone la URL interna de Supabase
ni el detalle de las excepciones al cliente.
"""

from __future__ import annotations

import requests
from fastapi import HTTPException, Request

from . import config, database

_ROL_FUERA = "Permisos insuficientes para esta acción"


def _h_auth() -> dict:
    return {
        "apikey": config.SUPABASE_ANON_KEY or config.SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type": "application/json",
    }


def validar_token(request: Request) -> dict:
    """Valida el JWT del usuario contra GoTrue. Devuelve el objeto user."""
    cabecera = request.headers.get("Authorization", "")
    if not cabecera.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Sesión requerida")
    token = cabecera[7:]

    apikey_auth = request.headers.get("apikey") or config.SUPABASE_ANON_KEY
    try:
        resp = requests.get(
            f"{config.SUPABASE_URL}/auth/v1/user",
            headers={"apikey": apikey_auth, "Authorization": f"Bearer {token}"},
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail="No se pudo validar la sesión") from exc
    if resp.status_code != 200:
        raise HTTPException(status_code=401, detail="Sesión inválida o expirada")
    return resp.json()


def perfil_de(user_id: str) -> dict | None:
    """Perfil del usuario (rol, unidad_id, activo) con service-role."""
    filas = database.obtener_perfil(user_id)
    return filas[0] if filas else None


def requerir_perfil(request: Request, roles: set[str] | None = None) -> dict:
    """Devuelve {user, perfil} o lanza 401/403.

    - Si 'roles' se indica, el perfil debe tener uno de esos roles y estar activo.
    - Si el usuario no tiene perfil, se rechaza (403) salvo roles vacíos.
    """
    user = validar_token(request)
    perfil = perfil_de(user["id"])

    if not perfil or not perfil.get("activo"):
        raise HTTPException(status_code=403, detail=_ROL_FUERA)

    if roles is not None and perfil.get("rol") not in roles:
        raise HTTPException(status_code=403, detail=_ROL_FUERA)

    return {"user": user, "perfil": perfil}


# ---------------------------------------------------------------
# Admin API de Supabase (service-role) para crear/administrar usuarios
# ---------------------------------------------------------------

def _h_service() -> dict:
    return {
        "apikey": config.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {config.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def generar_invitacion(email: str) -> None:
    """Genera y envía el correo de invitación (type=invite) al email.

    Para un email inexistente, GoTrue crea el usuario pendiente y la
    invitación; el trigger handle_new_user le crea el perfil rol='rt'.
    El invitado define su contraseña con el flujo existente de recuperación
    ("olvidé mi contraseña") una vez dentro de la app.
    """
    try:
        resp = requests.post(
            f"{config.SUPABASE_URL}/auth/v1/admin/generate_link",
            headers=_h_service(),
            json={
                "type": "invite",
                "email": email,
                "options": {"redirect_to": config.AUTH_REDIRECT_INVITAR_URL},
            },
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail="No se pudo enviar la invitación") from exc
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="El servidor de usuarios rechazó la invitación")


def enviar_recuperacion(email: str) -> None:
    """Reenvía un enlace de recuperación de contraseña (usuario existente)."""
    try:
        resp = requests.post(
            f"{config.SUPABASE_URL}/auth/v1/admin/generate_link",
            headers=_h_service(),
            json={
                "type": "recovery",
                "email": email,
                "options": {"redirect_to": config.AUTH_REDIRECT_URL},
            },
            timeout=30,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail="No se pudo enviar el enlace") from exc
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="El servidor de usuarios rechazó el enlace")