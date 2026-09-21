"""Migración inicial: Google Sheets -> Supabase PostgreSQL.

Lee las pestañas del libro de planilla (export CSV público) y carga en
Supabase, SIN perder el histórico:

  * UNIDAD, TURNO, NOMINA          -> catálogos + personas
  * ASIGNACION VACACIONES (109)    -> vacaciones
  * ASIGNACION LIBRES   (1390)     -> libres (agrupados en rangos)
  * LISTADO PERSONAL Y TURNOS      -> plan_mensual de los meses presentes
  * PLANILLA / REPORTE IMPRESION   -> derivadas (no se importan)
  * REPORTES                      -> no operativo

Requiere:
  - variables de entorno SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY
  - acceso de lectura público a las hojas (export format=csv)

Uso:
  setx SUPABASE_URL "https://TU-PROYECTO.supabase.co"
  setx SUPABASE_SERVICE_ROLE_KEY "tu_service_role_key"
  python importar_sheets.py
"""

import csv
import io
import os
from datetime import date, datetime, timedelta

import requests

ID_LIBRO = "1hGKq-jXFoAwOQvMKyIFlCLWMWUmF4q2aJVmZwg-nuU0"

HOJAS = {
    1371441161: "UNIDAD",
    696465106: "TURNO",
    1148693630: "NOMINA",
    1224886937: "VACACIONES",
    1659564203: "LIBRES",
    1201878621: "LISTADO",
    1954202234: "PLANILLA",
    1417240536: "REPORTE_IMPRESION",
    233885688: "REPORTES",
}

NUM_TURNO_A_CODIGO = {"1": "M", "2": "T", "3": "N1", "4": "N2", "5": "N3", "6": "D"}


def descargar(gid: int) -> list[list[str]]:
    url = f"https://docs.google.com/spreadsheets/d/{ID_LIBRO}/export?format=csv&gid={gid}"
    resp = requests.get(url, timeout=60)
    resp.raise_for_status()
    resp.encoding = "utf-8"
    lector = csv.reader(io.StringIO(resp.text))
    return [fila for fila in lector if any(str(c).strip() for c in fila)]


def enviar(tabla: str, filas: list[dict]) -> None:
    url = f"{os.environ['SUPABASE_URL']}/rest/v1/{tabla}"
    headers = {
        "apikey": os.environ["SUPABASE_SERVICE_ROLE_KEY"],
        "Authorization": f"Bearer {os.environ['SUPABASE_SERVICE_ROLE_KEY']}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }
    if filas:
        resp = requests.post(url, headers=headers, json=filas, timeout=120)
        resp.raise_for_status()


def leer(tabla: str) -> list[dict]:
    url = f"{os.environ['SUPABASE_URL']}/rest/v1/{tabla}"
    headers = {
        "apikey": os.environ["SUPABASE_SERVICE_ROLE_KEY"],
        "Authorization": f"Bearer {os.environ['SUPABASE_SERVICE_ROLE_KEY']}",
    }
    resp = requests.get(url, headers=headers, params={"select": "*", "limit": "10000"}, timeout=60)
    resp.raise_for_status()
    return resp.json()


def normalizar_ci(v) -> str:
    return "".join(ch for ch in str(v or "") if ch.isdigit())


def parsear_fecha(v) -> date | None:
    for fmt in ("%m/%d/%Y", "%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y"):
        try:
            return datetime.strptime(str(v).strip(), fmt).date()
        except ValueError:
            continue
    try:
        return date(1899, 12, 30) + timedelta(days=int(float(v)))
    except (ValueError, TypeError):
        return None


def main() -> None:
    faltantes = {"SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"} - set(os.environ)
    if faltantes:
        raise SystemExit(f"Faltan variables de entorno: {faltantes}")

    print("Descargando hojas...")
    unidades_raw = descargar(1371441161)
    turnos_raw = descargar(696465106)
    nomina = descargar(1148693630)
    vacaciones_raw = descargar(1224886937)
    libres_raw = descargar(1659564203)
    listado = descargar(1201878621)

    # ---------- catálogos ----------
    if not leer("unidades"):
        enviar("unidades", [{"nombre": f[1]} for f in unidades_raw[1:] if len(f) > 1 and f[1]])
    if not leer("turnos"):
        enviar("turnos", [
            {"codigo": codigo, "descripcion": codigo,
             "hora_inicio": "06:00" if codigo in ("M", "D") else "12:00" if codigo == "T" else "18:00",
             "hora_fin": "12:00" if codigo == "M" else "18:00" if codigo in ("T", "D") else "06:00"}
            for codigo in ("M", "T", "N1", "N2", "N3", "D")
        ])
    if not leer("sectores"):
        enviar("sectores", [
            {"unidad_id": 1, "nombre": "RAC"}, {"unidad_id": 1, "nombre": "INTERNADOS"},
            {"unidad_id": 2, "nombre": "SALA"},
        ])
    if not leer("cargos"):
        enviar("cargos", [{"nombre": n} for n in ("RT", "JEFATURA", "AUXILIAR")])

    unidades_db = {u["nombre"]: u["id"] for u in leer("unidades")}
    sectores_db = {(s["unidad_id"], s["nombre"]): s["id"] for s in leer("sectores")}
    cargos_db = {c["nombre"]: c["id"] for c in leer("cargos")}
    turnos_db = {t["codigo"]: t["id"] for t in leer("turnos")}

    # ---------- personas ----------
    if leer("personas"):
        print("personas ya cargadas; se omite.")
    else:
        encabezado = nomina[0]
        filas_personas = []
        orden_por_grupo: dict[tuple, int] = {}
        for fila in nomina[1:]:
            registro = dict(zip(encabezado, fila))
            nombre = (registro.get("PERSONAL") or "").strip()
            if not nombre:
                continue

            unidad_nombre = (registro.get("UNIDAD") or "").strip()
            sector_nombre = (registro.get("SECTOR") or "").strip()
            unidad_id = int(unidad_nombre) if unidad_nombre.isdigit() else None
            sector_id = sectores_db.get((unidad_id, sector_nombre)) if unidad_id is not None else None

            grupo = (unidad_id, sector_id)
            orden = orden_por_grupo.get(grupo, 0) + 1
            orden_por_grupo[grupo] = orden

            num_turno = (registro.get("TURNO") or "").strip()
            codigo_turno = NUM_TURNO_A_CODIGO.get(num_turno)

            filas_personas.append({
                "idpersonal_legacy": str(registro.get("id_NOMINA") or "").strip() or None,
                "nombre": nombre,
                "ci": normalizar_ci(registro.get("C.I. N\u00b0") or ""),
                "registro": (registro.get("Reg. N\u00b0") or "").strip(),
                "unidad_id": unidad_id,
                "sector_id": sector_id,
                "cargo_id": cargos_db.get((registro.get("CARGO") or "").strip()),
                "turno_id": turnos_db.get(codigo_turno) if codigo_turno else None,
                "estado": (registro.get("ESTADO") or "ACTIVO").upper(),
                "orden": orden,
            })
        enviar("personas", filas_personas)
        print(f"personas importadas: {len(filas_personas)}")

    personas_db = leer("personas")
    personas_por_ci = {}
    for p in personas_db:
        ci = normalizar_ci(p.get("ci") or "")
        personas_por_ci.setdefault(ci, p["id"])

    # ---------- vacaciones ----------
    if leer("vacaciones"):
        print("vacaciones ya cargadas; se omite.")
    else:
        encabezado_v = vacaciones_raw[0]
        filas_vac = []
        for fila in vacaciones_raw[1:]:
            reg = dict(zip(encabezado_v, fila))
            pid = personas_por_ci.get(normalizar_ci(reg.get("nroCI")))
            if pid is None:
                print(f"  [aviso] vacación sin persona: {reg.get('PERSONAL')}")
                continue
            ini = parsear_fecha(reg.get("FECHA INICIO"))
            fin = parsear_fecha(reg.get("FECHA FIN"))
            if not ini or not fin:
                continue
            filas_vac.append({
                "persona_id": pid,
                "fecha_inicio": ini.isoformat(),
                "fecha_fin": fin.isoformat(),
                "observacion": (reg.get("mensaje") or "").strip() or None,
            })
        enviar("vacaciones", filas_vac)
        print(f"vacaciones importadas: {len(filas_vac)}")

    # ---------- libres ----------
    if leer("libres"):
        print("libres ya cargados; se omite.")
    else:
        encabezado_l = libres_raw[0]
        por_persona: dict[int, list[date]] = {}
        for fila in libres_raw[1:]:
            reg = dict(zip(encabezado_l, fila))
            pid = personas_por_ci.get(normalizar_ci(reg.get("nroCI")))
            if pid is None:
                continue
            fecha = parsear_fecha(reg.get("fecha"))
            if fecha:
                por_persona.setdefault(pid, []).append(fecha)

        filas_lib = []
        for pid, fechas in por_persona.items():
            unicas = sorted({f for f in fechas})
            inicio = fin = unicas[0]
            for f in unicas[1:]:
                if f == fin + timedelta(days=1):
                    fin = f
                else:
                    filas_lib.append({"persona_id": pid, "fecha_inicio": inicio.isoformat(), "fecha_fin": fin.isoformat()})
                    inicio = fin = f
            filas_lib.append({"persona_id": pid, "fecha_inicio": inicio.isoformat(), "fecha_fin": fin.isoformat()})
        enviar("libres", filas_lib)
        print(f"libres importados (agrupados en {len(filas_lib)} rangos)")

    # ---------- plan mensual ----------
    if leer("plan_mensual"):
        print("plan_mensual ya cargado; se omite.")
    else:
        encabezado_t = listado[0]
        # columnas de fecha en cabecera
        fecha_cols: list[tuple[int, date]] = []
        for idx, celda in enumerate(encabezado_t[10:], start=10):
            f = parsear_fecha(celda)
            if f:
                fecha_cols.append((idx, f))
        if not fecha_cols:
            print("  [aviso] sin columnas de fecha en LISTADO; plan no importado.")
            return

        personas_legacy = {str(p.get("idpersonal_legacy")): p["id"] for p in personas_db if p.get("idpersonal_legacy")}
        personas_nombre = {p["nombre"]: p["id"] for p in personas_db}
        try:
            idx_idpersonal = encabezado_t.index("idpersonal")
        except ValueError:
            idx_idpersonal = -1
        try:
            idx_nombre = encabezado_t.index("personal")
        except ValueError:
            idx_nombre = -1

        filas_plan = []
        for fila in listado[1:]:
            pid = None
            if idx_idpersonal >= 0:
                pid = personas_legacy.get(str(fila[idx_idpersonal]).strip())
            if pid is None and idx_nombre >= 0:
                pid = personas_nombre.get((fila[idx_nombre] or "").strip())
            if pid is None:
                continue
            for idx, f in fecha_cols:
                codigo = fila[idx].strip()
                if codigo in turnos_db:
                    filas_plan.append({"persona_id": pid, "fecha": f.isoformat(), "turno_id": turnos_db[codigo]})
        enviar("plan_mensual", filas_plan)
        fechas = [f for _, f in fecha_cols]
        print(f"plan_mensual importado: {len(filas_plan)} celdas "
              f"({min(fechas)} → {max(fechas)})")

    print("Migración completada.")


if __name__ == "__main__":
    main()