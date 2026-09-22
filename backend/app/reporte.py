"""Lógica de generación del reporte mensual de guardia.

Reglas de prioridad por celda (de mayor a menor):
  1. Vacaciones  -> celda combinada "VACACIONES DESDE ... HASTA ..."
  2. Libres      -> "L"
  3. Turno       -> M / T / N1 / N2 / N3 / D (del plan mensual)
  4. Sin asignar -> vacío
"""

from __future__ import annotations

import calendar
import copy
from datetime import date, datetime

from jinja2 import Environment, FileSystemLoader, select_autoescape

from . import config


def _parse_ids(value) -> list[int]:
    if not value:
        return []
    if isinstance(value, (int, str)):
        return [int(value)]
    return [int(v) for v in value]


def dias_del_mes(anio: int, mes: int) -> list[date]:
    _, total = calendar.monthrange(anio, mes)
    return [date(anio, mes, dia) for dia in range(1, total + 1)]


def _superposicion(dias: list[date], fecha_ini: date, fecha_fin: date) -> tuple[int, int] | None:
    """Devuelve (indice_inicio, indice_fin) de la superposición, o None."""
    ini = None
    fin = None
    for idx, dia in enumerate(dias):
        if fecha_ini <= dia <= fecha_fin:
            if ini is None:
                ini = idx
            fin = idx
    if ini is None:
        return None
    return ini, fin


def _agrupar_vacaciones(celdas: list, indices: list[int], texto: str, total: int) -> None:
    """Reemplaza varias celdas contiguas por una celda 'vacaciones' con colspan."""
    for i in indices:
        celdas[i] = None

    # reagrupar por contigüidad
    bloques: list[list[int]] = []
    actual: list[int] = []
    for i in sorted(indices):
        if actual and i == actual[-1] + 1:
            actual.append(i)
        else:
            if actual:
                bloques.append(actual)
            actual = [i]
    if actual:
        bloques.append(actual)

    for bloque in bloques:
        celdas[bloque[0]] = {
            "tipo": "vacaciones",
            "colspan": len(bloque),
            "texto": texto,
        }


def _grupo_turno(persona: dict) -> int:
    """Orden de la planilla por tipo de turno: M, T, N1-3, D y otros al final."""
    orden_turno = {"M": 0, "T": 1, "N1": 2, "N2": 3, "N3": 4, "D": 5}
    codigo = (persona.get("turno") or {}).get("codigo")
    return orden_turno.get(codigo, 6)


def construir_filas(
    personas: list[dict],
    vacaciones: list[dict],
    libres: list[dict],
    plan: list[dict],
    turnos: list[dict],
    anio: int,
    mes: int,
) -> tuple[list[dict], list[date]]:
    dias = dias_del_mes(anio, mes)
    n = len(dias)

    # Orden de la planilla: primero por grupo de turno (mañana, tarde,
    # noches 1-2-3, fin de semana) y dentro de cada grupo por unidad,
    # número de orden y nombre.
    personas = sorted(
        personas,
        key=lambda p: (
            _grupo_turno(p),
            p.get("unidad_id") is not None,
            p.get("unidad_id") or 0,
            p.get("orden") or 0,
            p.get("nombre") or "",
        ),
    )

    codigo_turno = {t["id"]: t["codigo"] for t in turnos}
    horario_turno = {
        t["codigo"]: f"{t['hora_inicio'][:5]} - {t['hora_fin'][:5]}"
        for t in turnos
    }

    # Índices por persona
    vac_x_persona: dict[int, list] = {}
    for v in vacaciones:
        vac_x_persona.setdefault(v["persona_id"], []).append(
            (datetime.fromisoformat(v["fecha_inicio"]).date(),
             datetime.fromisoformat(v["fecha_fin"]).date(),
             v.get("observacion"))
        )

    lib_x_persona: dict[int, list] = {}
    for l in libres:
        lib_x_persona.setdefault(l["persona_id"], []).append(
            (datetime.fromisoformat(l["fecha_inicio"]).date(),
             datetime.fromisoformat(l["fecha_fin"]).date(),
             l.get("motivo"))
        )

    plan_x_persona: dict[int, dict] = {}
    for p in plan:
        plan_x_persona.setdefault(p["persona_id"], {})[
            datetime.fromisoformat(p["fecha"]).date()
        ] = codigo_turno.get(p.get("turno_id") or p.get("turno", {}).get("id")) or p.get("turno", {}).get("codigo")

    filas = []
    for persona in personas:
        hora_base = ""
        turno_base_codigo = (persona.get("turno") or {}).get("codigo")
        if turno_base_codigo:
            hora_base = horario_turno.get(turno_base_codigo, "")

        cargo_nombre = (persona.get("cargo") or {}).get("nombre") or ""
        sector_nombre = (persona.get("sector") or {}).get("nombre") or ""
        nombre_completo = " ".join(
            parte for parte in [persona["nombre"], cargo_nombre, sector_nombre] if parte
        )

        celdas = [{"tipo": "dato", "valor": ""} for _ in range(n)]

        # 1) Vacaciones
        for (ini, fin, obs) in vac_x_persona.get(persona["id"], []):
            sup = _superposicion(dias, ini, fin)
            if not sup:
                continue
            idx_ini, idx_fin = sup
            texto = f"VACACIONES DESDE {ini.strftime('%d/%m/%Y')} HASTA {fin.strftime('%d/%m/%Y')}"
            _agrupar_vacaciones(celdas, list(range(idx_ini, idx_fin + 1)), texto, n)

        # 2) Libres
        for (ini, fin, motivo) in lib_x_persona.get(persona["id"], []):
            sup = _superposicion(dias, ini, fin)
            if not sup:
                continue
            idx_ini, idx_fin = sup
            for i in range(idx_ini, idx_fin + 1):
                celda = celdas[i]
                if celda is None:
                    continue  # ya hay vacaciones
                if celda["tipo"] == "dato":
                    celda["valor"] = "L"

        # 3) Turno del plan
        for idx, dia in enumerate(dias):
            celda = celdas[idx]
            if celda is None or celda["tipo"] != "dato":
                continue
            cod = plan_x_persona.get(persona["id"], {}).get(dia)
            if cod and not celda["valor"]:
                celda["valor"] = cod

        filas.append({
            "nombre": nombre_completo,
            "ci": persona.get("ci") or "",
            "registro": persona.get("registro") or "",
            "horario": hora_base,
            "celdas": celdas,
        })

    return filas, dias


def renderizar_html(filas: list[dict], dias: list[date], anio: int, mes: int, titulo: str) -> str:
    env = Environment(
        loader=FileSystemLoader(config.TEMPLATES_DIR),
        autoescape=select_autoescape(["html"]),
    )
    template = env.get_template("reporte.html")
    return template.render(
        institucion=config.INSTITUCION,
        institucion_sub=config.INSTITUCION_SUB,
        observacion=config.OBSERVACION,
        firmas=config.FIRMAS,
        mes_nombre=config.MESES_ES[mes - 1],
        anio=anio,
        titulo=titulo,
        dias=dias,
        dias_semana_es=config.DIAS_SEMANA_ES,
        filas=filas,
    )


def generar_pdf(html: str, anio: int, mes: int, unidad_nombre: str) -> bytes:
    from weasyprint import HTML as WeasyHTML  # import diferido: opcional

    base_url = config.ASSETS_DIR
    documento = WeasyHTML(string=html, base_url=base_url)
    return documento.write_pdf()


def nombre_archivo_pdf(unidad_nombre: str, anio: int, mes: int) -> str:
    """Nombre de archivo sugerido: 'planilla urgencias octubre 2026.pdf'."""
    slug = (unidad_nombre or "completa").lower()
    mes_nombre = config.MESES_ES[mes - 1].lower()
    return f"planilla {slug} {mes_nombre} {anio}.pdf"


def generar_reporte(
    anio: int,
    mes: int,
    datos: dict,
    unidad_ids: list[int],
    sector_ids: list[int],
    formato: str = "html",
) -> tuple[str | bytes, str, str]:
    unidades_nombre = {
        u["id"]: u["nombre"] for u in datos["unidades"]
        if u["id"] in (unidad_ids or [u["id"] for u in datos["unidades"]])
    }

    unidad_nombre = " / ".join(unidades_nombre.values())
    titulo = unidad_nombre

    filas, dias = construir_filas(
        personas=datos["personas"],
        vacaciones=datos["vacaciones"],
        libres=datos["libres"],
        plan=datos["plan"],
        turnos=datos["turnos"],
        anio=anio,
        mes=mes,
    )

    html = renderizar_html(filas, dias, anio, mes, titulo)

    if formato == "pdf":
        try:
            pdf = generar_pdf(html, anio, mes, unidad_nombre)
            return pdf, "application/pdf", unidad_nombre
        except Exception as exc:  # weasyprint no disponible -> HTML
            print(f"[aviso] No se pudo generar PDF ({exc}); se devuelve HTML.")
            return html, "text/html", unidad_nombre

    return html, "text/html", unidad_nombre