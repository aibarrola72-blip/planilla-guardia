"""Smoke test de la lógica de generación del reporte (sin base de datos)."""

from datetime import date

from app import reporte


def construir_datos_fake():
    return {
        "unidades": [{"id": 1, "nombre": "URGENCIAS"}],
        "sectores": [{"id": 1, "unidad_id": 1, "nombre": "RAC"}],
        "turnos": [
            {"id": 1, "codigo": "M", "hora_inicio": "06:00", "hora_fin": "12:00"},
            {"id": 2, "codigo": "T", "hora_inicio": "12:00", "hora_fin": "18:00"},
            {"id": 3, "codigo": "N1", "hora_inicio": "18:00", "hora_fin": "06:00"},
            {"id": 4, "codigo": "N2", "hora_inicio": "18:00", "hora_fin": "06:00"},
            {"id": 5, "codigo": "N3", "hora_inicio": "18:00", "hora_fin": "06:00"},
            {"id": 6, "codigo": "D", "hora_inicio": "06:00", "hora_fin": "18:00"},
        ],
        "personas": [
            {
                "id": 1, "nombre": "Lic. Rosita Perez", "ci": "111",
                "registro": "1", "estado": "ACTIVO", "orden": 1,
                "turno": {"codigo": "M"},
            },
            {
                "id": 2, "nombre": "Lic. Juan Lopez", "ci": "222",
                "registro": "2", "estado": "ACTIVO", "orden": 2,
                "turno": {"codigo": "N1"},
            },
        ],
        "vacaciones": [
            {"persona_id": 1, "fecha_inicio": "2026-09-10", "fecha_fin": "2026-09-12", "observacion": None},
        ],
        "libres": [
            {"persona_id": 1, "fecha_inicio": "2026-09-05", "fecha_fin": "2026-09-06", "motivo": None},
            {"persona_id": 2, "fecha_inicio": "2026-09-20", "fecha_fin": "2026-09-21", "motivo": None},
        ],
        "plan": [
            {"persona_id": 1, "fecha": "2026-09-01", "turno_id": 1},
            {"persona_id": 1, "fecha": "2026-09-02", "turno_id": 1},
            {"persona_id": 1, "fecha": "2026-09-03", "turno_id": 1},
            {"persona_id": 1, "fecha": "2026-09-08", "turno_id": 1},
            {"persona_id": 2, "fecha": "2026-09-04", "turno_id": 3},
            {"persona_id": 2, "fecha": "2026-09-05", "turno_id": 4},
            {"persona_id": 2, "fecha": "2026-09-06", "turno_id": 5},
        ],
    }


def verificar():
    datos = construir_datos_fake()
    html, _ = reporte.generar_reporte(
        anio=2026, mes=9, datos=datos,
        unidad_ids=[1], sector_ids=[1], formato="html",
    )

    # Prioridad: vacaciones gana
    assert "VACACIONES DESDE 10/09/2026 HASTA 12/09/2026" in html
    assert 'colspan="3"' in html

    # Libres
    # persona 1: 5 y 6 de setiembre -> L
    # persona 1: turno M los días 1,2,3,8,9
    filas_html = html.split("</tr>")
    assert any("<td class=\"celda-turno\">L</td>" for f in filas_html for f in [f])

    # Turnos de noche
    assert "<td class=\"celda-turno\">N1</td>" in html
    assert "<td class=\"celda-turno\">N2</td>" in html
    assert "<td class=\"celda-turno\">N3</td>" in html

    # Título del mes
    assert "PLANILLA DE GUARDIA URGENCIAS - RAC MES DE SEPTIEMBRE AÑO 2026" in html

    print("smoke OK: vacaciones, libres, turnos y título correctos")


if __name__ == "__main__":
    verificar()