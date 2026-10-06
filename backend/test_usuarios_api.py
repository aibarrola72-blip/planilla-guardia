"""Tests de creación/invitación de usuarios desde el panel (sin red).

Se ejecutan como script (convención del repo) o con pytest si está instalado:

    python test_usuarios_api.py
"""

from __future__ import annotations

import contextlib
from unittest import mock

from fastapi import HTTPException

from app import main as m


def _perfil_admin() -> dict:
    return {
        "user_id": "admin-1", "rol": "admin", "unidad_id": None,
        "unidades": [], "persona_id": None, "activo": True,
    }


def _instalar(
    stack: contextlib.ExitStack,
    persona: dict | None,
    *,
    existente: bool = False,
    perfil_faltante: bool = False,
    error_envio: bool = False,
) -> dict:
    """Reemplaza la red (Supabase Auth + PostgREST) y devuelve el registro de llamadas."""
    llamadas: dict = {"campos": None, "unidades": None, "creado": None}
    usuario = {"id": "u-1", "email": "rt@ineram.com"}
    vistos = {"n": 0}

    def buscar(_email: str) -> dict | None:
        vistos["n"] += 1
        return usuario if (existente or vistos["n"] > 1) else None

    def envio_fallido(_email: str) -> None:
        raise HTTPException(status_code=502, detail="No se pudo enviar el enlace")

    parches = [
        mock.patch.object(m, "_buscar_usuario_por_email", side_effect=buscar),
        mock.patch.object(m.seguridad, "generar_invitacion"),
        mock.patch.object(
            m.seguridad, "enviar_recuperacion",
            side_effect=envio_fallido if error_envio else None,
        ),
        mock.patch.object(
            m.seguridad, "requerir_perfil",
            side_effect=lambda request, roles: {"perfil": _perfil_admin()},
        ),
        mock.patch.object(m.database, "obtener_persona", side_effect=lambda pid: persona),
        mock.patch.object(
            m.database, "obtener_perfil",
            side_effect=lambda uid: [] if perfil_faltante else [{"user_id": uid}],
        ),
        mock.patch.object(m.database, "actualizar_perfil",
                          side_effect=lambda uid, campos: llamadas.update(campos=campos)),
        mock.patch.object(
            m.database, "crear_filas",
            side_effect=lambda tabla, filas: llamadas.update(creado=filas),
        ),
        mock.patch.object(m.database, "reemplazar_unidades",
                          side_effect=lambda uid, unidades: llamadas.update(unidades=unidades)),
    ]
    for p in parches:
        stack.enter_context(p)
    return llamadas


def test_post_usuarios_reenvia_persona_id() -> None:
    """El panel envía persona_id y el backend debe usarla (unidad + vínculo)."""
    with contextlib.ExitStack() as stack:
        llamadas = _instalar(stack, {"id": 7, "nombre": "Lic. Ana", "unidad_id": 3, "turno_id": 1})

        body = m.UsuarioRequest(email="rt@ineram.com", rol="rt", persona_id=7)
        rta = m.crear_usuario(body, request=None)  # requerir_perfil parcheado

        assert rta["persona_id"] == 7
        assert rta["unidad_id"] == 3            # unidad derivada de la persona
        assert rta["unidades"] == [3]
        assert llamadas["campos"]["persona_id"] == 7
        assert llamadas["campos"]["unidad_id"] == 3
        assert llamadas["unidades"] == [3]


def test_post_usuarios_sin_unidad_y_sin_persona_falla() -> None:
    """Regresión: RT sin chips y sin persona sigue pidiendo unidad."""
    with contextlib.ExitStack() as stack:
        _instalar(stack, None)

        body = m.UsuarioRequest(email="rt@ineram.com", rol="rt")
        try:
            m.crear_usuario(body, request=None)
        except HTTPException as exc:
            assert exc.status_code == 400
            assert exc.detail == "Un RT necesita unidad asignada"
        else:
            raise AssertionError("debia fallar con 400")


def test_persona_sin_unidad_rechazada() -> None:
    """Una persona sin unidad no puede generar un perfil con unidad NULL."""
    with contextlib.ExitStack() as stack:
        _instalar(stack, {"id": 7, "nombre": "Lic. Ana", "unidad_id": None, "turno_id": None})

        body = m.UsuarioRequest(email="rt@ineram.com", rol="rt", persona_id=7)
        try:
            m.crear_usuario(body, request=None)
        except HTTPException as exc:
            assert exc.status_code == 400
            assert exc.detail == "La persona no tiene unidad asignada"
        else:
            raise AssertionError("debia fallar con 400")


def test_patch_persona_sin_unidad_rechazada() -> None:
    """PATCH /api/usuarios/{id} con persona sin unidad tampoco debe romper el perfil."""
    with contextlib.ExitStack() as stack:
        _instalar(stack, {"id": 7, "nombre": "Lic. Ana", "unidad_id": None, "turno_id": None})

        body = m.UsuarioPatch(persona_id=7)
        try:
            m.actualizar_usuario("u-1", body, request=None)
        except HTTPException as exc:
            assert exc.status_code == 400
            assert exc.detail == "La persona no tiene unidad asignada"
        else:
            raise AssertionError("debia fallar con 400")


def test_persona_se_asocia_a_rol_no_rt() -> None:
    """Cualquier rol admite vínculo persona (alimenta la firma 'jefe_unidad')."""
    with contextlib.ExitStack() as stack:
        llamadas = _instalar(stack, {"id": 7, "nombre": "Lic. Ana", "unidad_id": 3, "turno_id": 1})

        body = m.UsuarioRequest(
            email="jefe@ineram.com", rol="jefe", persona_id=7, unidades=[5])
        rta = m.crear_usuario(body, request=None)

        assert rta["persona_id"] == 7
        assert llamadas["campos"]["persona_id"] == 7
        assert llamadas["campos"]["unidad_id"] == 5   # mandan los chips, no la persona
        assert llamadas["unidades"] == [5]


def test_email_existente_vincula_aunque_falle_el_correo() -> None:
    """El reenvío a un usuario ya registrado no puede impedir guardar el vínculo."""
    with contextlib.ExitStack() as stack:
        llamadas = _instalar(
            stack, {"id": 7, "nombre": "Lic. Ana", "unidad_id": 3, "turno_id": 1},
            existente=True, error_envio=True)

        body = m.UsuarioRequest(email="rt@ineram.com", rol="rt", persona_id=7)
        rta = m.crear_usuario(body, request=None)

        assert llamadas["campos"]["persona_id"] == 7
        assert rta["aviso"] == "No se pudo enviar el enlace"


def test_crea_el_perfil_si_no_existe() -> None:
    """Usuario sin fila en perfiles: se crea en vez de ignorar el guardado."""
    with contextlib.ExitStack() as stack:
        llamadas = _instalar(
            stack, {"id": 7, "nombre": "Lic. Ana", "unidad_id": 3, "turno_id": 1},
            perfil_faltante=True)

        body = m.UsuarioRequest(email="rt@ineram.com", rol="rt", persona_id=7)
        m.crear_usuario(body, request=None)

        assert llamadas["campos"] is None          # no hubo UPDATE
        creado = llamadas["creado"]
        assert creado and creado[0]["user_id"] == "u-1"
        assert creado[0]["persona_id"] == 7
        assert creado[0]["unidad_id"] == 3


if __name__ == "__main__":
    test_post_usuarios_reenvia_persona_id()
    test_post_usuarios_sin_unidad_y_sin_persona_falla()
    test_persona_sin_unidad_rechazada()
    test_patch_persona_sin_unidad_rechazada()
    test_persona_se_asocia_a_rol_no_rt()
    test_email_existente_vincula_aunque_falle_el_correo()
    test_crea_el_perfil_si_no_existe()
    print("usuarios OK: persona_id en cualquier rol, escritura previa al correo")
