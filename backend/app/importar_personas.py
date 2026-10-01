"""Núcleo de importación masiva de personal desde Excel (NOMINA) -> Supabase.

Fuente única de verdad; la consumen dos caras:
  * CLI ............ migracion/importar_excel.py   (dry-run por defecto)
  * Panel admin .... POST /api/admin/importar-personas (vista previa + aplicar)

Estrategia MERGE + bajas como INACTIVO (nunca DELETE: vacaciones, libres y
plan_mensual cuelgan de personas con on delete cascade).

Cruce por persona (en orden, fail-safe):
  1. idpersonal_legacy  2. CI normalizada (solo si es única en BD)
  3. nombre + unidad_id
  Ambiguo / CI duplicada / fila repetida -> "revision" y NO se importa.
"""

from __future__ import annotations

import io
import unicodedata
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from openpyxl import load_workbook

from . import database

NUM_TURNO_A_CODIGO = {"1": "M", "2": "T", "3": "N1", "4": "N2", "5": "N3", "6": "D"}
RANGO_AUSENCIAS = ("2000-01-01", "2100-12-31")
MAX_FILAS_DEFECTO = 5000


class ErrorImportacion(ValueError):
    """Entrada inválida (hoja ausente/vacía, sin columna de nombre, demasiadas filas)."""


def normalizar_ci(v) -> str:
    return "".join(ch for ch in str(v or "") if ch.isdigit())


def normalizar_nombre(v) -> str:
    s = str(v or "").strip().lower()
    return "".join(ch for ch in unicodedata.normalize("NFKD", s) if not unicodedata.combining(ch))


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


ALIAS_COLUMNA = {
    "nombre": ("personal", "nombre", "nombre y apellido"),
    "id_legacy": ("id_nomina", "idpersonal", "idpersonal_legacy"),
    "ci": ("c.i. n\u00b0", "ci", "c.i.", "cedula"),
    "registro": ("reg. n\u00b0", "registro", "reg"),
    "unidad": ("unidad",),
    "sector": ("sector",),
    "cargo": ("cargo",),
    "turno": ("turno",),
    "estado": ("estado",),
    "nro_ci": ("nroci", "ci", "c.i. n\u00b0"),
    "fecha_inicio": ("fecha inicio", "inicio"),
    "fecha_fin": ("fecha fin", "fin"),
    "fecha": ("fecha",),
    "mensaje": ("mensaje", "observacion"),
}


# ---------------------------------------------------------------- lectura ---

def _txt(celda) -> str:
    """Celda -> texto estable (12345.0 -> '12345'; evita CIs corruptas)."""
    if celda is None:
        return ""
    if isinstance(celda, datetime):
        return celda.date().isoformat()
    if isinstance(celda, date):
        return celda.isoformat()
    if isinstance(celda, float) and celda.is_integer():
        return str(int(celda))
    return str(celda).strip()


def leer_hoja(wb, nombre: str) -> list[list[str]]:
    hoja = next(
        (wb[n] for n in wb.sheetnames if n.strip().casefold() == nombre.strip().casefold()),
        None,
    )
    if hoja is None:
        raise ErrorImportacion(
            f"No existe la hoja '{nombre}'. Disponibles: {', '.join(wb.sheetnames)}")
    filas: list[list[str]] = []
    for fila in hoja.iter_rows(values_only=True):
        celdas = [_txt(c) for c in fila]
        if any(celdas):
            filas.append(celdas)
    if not filas:
        raise ErrorImportacion(f"La hoja '{nombre}' esta vacia.")
    return filas


def _col(encabezados: list[str], campo: str) -> int | None:
    indice = {normalizar_nombre(h): i for i, h in enumerate(encabezados)}
    for alias in ALIAS_COLUMNA[campo]:
        i = indice.get(normalizar_nombre(alias))
        if i is not None:
            return i
    return None


def _mapa(encabezados: list[str]) -> dict[str, int | None]:
    return {campo: _col(encabezados, campo) for campo in ALIAS_COLUMNA}


def _valor(fila: list[str], mapa: dict[str, int | None], campo: str) -> str:
    i = mapa.get(campo)
    if i is None or i >= len(fila):
        return ""
    return fila[i].strip()


@dataclass
class FilaPersonal:
    linea: int
    nombre: str
    id_legacy: str | None = None
    ci: str = ""
    registro: str = ""
    unidad: str = ""
    sector: str = ""
    cargo: str = ""
    turno: str = ""
    estado: str = "ACTIVO"


def leer_nomina(filas: list[list[str]]) -> list[FilaPersonal]:
    mapa = _mapa(filas[0])
    if mapa["nombre"] is None:
        raise ErrorImportacion(f"La hoja no tiene columna de nombre. Cabecera: {filas[0]}")
    out: list[FilaPersonal] = []
    for n, fila in enumerate(filas[1:], start=2):
        nombre = _valor(fila, mapa, "nombre")
        if not nombre:
            continue
        estado = (_valor(fila, mapa, "estado") or "ACTIVO").upper()
        if estado not in ("ACTIVO", "INACTIVO"):
            estado = "ACTIVO"
        out.append(FilaPersonal(
            linea=n,
            nombre=nombre,
            id_legacy=_valor(fila, mapa, "id_legacy") or None,
            ci=normalizar_ci(_valor(fila, mapa, "ci")),
            registro=_valor(fila, mapa, "registro"),
            unidad=_valor(fila, mapa, "unidad"),
            sector=_valor(fila, mapa, "sector"),
            cargo=_valor(fila, mapa, "cargo"),
            turno=_valor(fila, mapa, "turno"),
            estado=estado,
        ))
    if not out:
        raise ErrorImportacion("La hoja no tiene filas de personal.")
    return out


def leer_ausencias(
    filas: list[list[str]], tipo: str
) -> list[tuple[str, str, date | None, date | None, str]]:
    """tipo='vacaciones' -> (ci, nombre, ini, fin, obs); tipo='libres' -> fin=None."""
    mapa = _mapa(filas[0])
    if mapa["nombre"] is None and mapa["nro_ci"] is None:
        raise ErrorImportacion(f"Hoja de {tipo} sin columnas reconocidas: {filas[0]}")
    out = []
    for fila in filas[1:]:
        ci = normalizar_ci(_valor(fila, mapa, "nro_ci"))
        nombre = _valor(fila, mapa, "nombre")
        if not ci and not nombre:
            continue
        if tipo == "vacaciones":
            ini = parsear_fecha(_valor(fila, mapa, "fecha_inicio"))
            fin = parsear_fecha(_valor(fila, mapa, "fecha_fin"))
            if ini and fin and fin < ini:
                ini, fin = fin, ini
            out.append((ci, nombre, ini, fin, _valor(fila, mapa, "mensaje")))
        else:
            out.append((ci, nombre, parsear_fecha(_valor(fila, mapa, "fecha")), None, ""))
    return out


# ------------------------------------------------------------- catálogos ---

@dataclass
class Catalogos:
    unidades: dict[str, int] = field(default_factory=dict)          # nombre -> id
    nombres_unidad: dict[int, str] = field(default_factory=dict)
    sectores: dict[tuple[int, str], int] = field(default_factory=dict)
    cargos: dict[str, int] = field(default_factory=dict)
    turnos: dict[str, int] = field(default_factory=dict)            # codigo -> id

    def refrescar(self) -> None:
        self.unidades = {normalizar_nombre(u["nombre"]): u["id"] for u in database.obtener_unidades()}
        self.nombres_unidad = {u["id"]: u["nombre"] for u in database.obtener_unidades()}
        self.sectores = {
            (s["unidad_id"], normalizar_nombre(s["nombre"])): s["id"]
            for s in database.obtener_sectores()
        }
        self.cargos = {normalizar_nombre(c["nombre"]): c["id"] for c in database.obtener_cargos()}
        self.turnos = {t["codigo"]: t["id"] for t in database.obtener_turnos()}

    def id_unidad(self, nombre: str) -> int | None:
        return self.unidades.get(normalizar_nombre(nombre)) if nombre else None

    def id_sector(self, unidad_id: int | None, nombre: str) -> int | None:
        if unidad_id is None or not nombre:
            return None
        return self.sectores.get((unidad_id, normalizar_nombre(nombre)))

    def id_cargo(self, nombre: str) -> int | None:
        return self.cargos.get(normalizar_nombre(nombre)) if nombre else None

    def id_turno(self, crudo: str) -> int | None:
        codigo = (crudo or "").strip().upper()
        if codigo in NUM_TURNO_A_CODIGO.values():
            return self.turnos.get(codigo)
        codigo = NUM_TURNO_A_CODIGO.get(codigo, "")
        return self.turnos.get(codigo) or None


def catalogos_faltantes(filas: list[FilaPersonal], cat: Catalogos) -> dict[str, list[dict]]:
    """Unidades/sectores/cargos del archivo que no existen en BD (deduplicados)."""
    faltan: dict[str, list[dict]] = {"unidades": [], "sectores": [], "cargos": []}
    vistas_u: set[str] = set()
    vistas_s: set[tuple[int, str]] = set()
    vistas_c: set[str] = set()
    for f in filas:
        ku = normalizar_nombre(f.unidad)
        if f.unidad and ku not in cat.unidades and ku not in vistas_u:
            vistas_u.add(ku)
            faltan["unidades"].append({"nombre": f.unidad})
        uid = cat.id_unidad(f.unidad)
        ks = (uid, normalizar_nombre(f.sector))
        if uid is not None and f.sector and ks not in cat.sectores and ks not in vistas_s:
            vistas_s.add(ks)
            faltan["sectores"].append({"unidad_id": uid, "nombre": f.sector})
        kc = normalizar_nombre(f.cargo)
        if f.cargo and kc not in cat.cargos and kc not in vistas_c:
            vistas_c.add(kc)
            faltan["cargos"].append({"nombre": f.cargo})
    return faltan


def preparar_catalogos(filas: list[FilaPersonal], cat: Catalogos) -> dict[str, list[dict]]:
    """Crea los catálogos faltantes (idempotente) y refresca los mapas."""
    faltan = catalogos_faltantes(filas, cat)
    if faltan["unidades"]:
        database.crear_filas("unidades", faltan["unidades"])
        cat.refrescar()
        faltan["sectores"] = catalogos_faltantes(filas, cat)["sectores"]
    if faltan["sectores"]:
        database.crear_filas("sectores", faltan["sectores"])
    if faltan["cargos"]:
        database.crear_filas("cargos", faltan["cargos"])
    if any(faltan.values()):
        cat.refrescar()
    return faltan


# --------------------------------------------------------------- cambios ---

@dataclass
class Cambios:
    altas: list[dict] = field(default_factory=list)
    mods: list[tuple[int, dict, dict]] = field(default_factory=list)   # id, nuevos, viejos
    bajas: list[tuple[int, str]] = field(default_factory=list)         # id, nombre
    revision: list[str] = field(default_factory=list)


@dataclass
class Ausencias:
    vacaciones: list[dict] = field(default_factory=list)
    libres: list[dict] = field(default_factory=list)
    omitidas: list[str] = field(default_factory=list)


def _pon(indice: dict, clave, persona: dict) -> None:
    """Guarda la persona; si la clave se repite la marca ambigua (None)."""
    if clave in indice:
        indice[clave] = None
    else:
        indice[clave] = persona


def _indice_personas(bd: list[dict]) -> dict:
    """Índices de cruce: legacy, CI (solo únicas), nombre, nombre+unidad."""
    por_legacy: dict[str, dict] = {}
    cuenta_ci: dict[str, int] = {}
    ci2p: dict[str, dict] = {}
    por_nombre: dict[str, dict | None] = {}
    por_nombre_unidad: dict[tuple[str, int | None], dict | None] = {}
    for p in bd:
        if p.get("idpersonal_legacy"):
            por_legacy[str(p["idpersonal_legacy"])] = p
        ci = normalizar_ci(p.get("ci") or "")
        if ci:
            cuenta_ci[ci] = cuenta_ci.get(ci, 0) + 1
            ci2p[ci] = p
        nombre = normalizar_nombre(p.get("nombre") or "")
        if nombre:
            _pon(por_nombre, nombre, p)
            _pon(por_nombre_unidad, (nombre, p.get("unidad_id")), p)
    return {
        "legacy": por_legacy,
        "cuenta_ci": cuenta_ci,
        "ci": {c: ci2p[c] for c, n in cuenta_ci.items() if n == 1},
        "nombre": por_nombre,
        "nombre_unidad": por_nombre_unidad,
    }


def _resolver_ids(f: FilaPersonal, cat: Catalogos) -> tuple[dict, list[str]]:
    """Ids de catálogo de una fila. Campo con texto que no resuelve -> problema."""
    ids: dict[str, int | None] = {}
    problemas: list[str] = []
    unidad_id = cat.id_unidad(f.unidad)
    if f.unidad and unidad_id is None:
        problemas.append(f"unidad '{f.unidad}' no existe")
    ids["unidad_id"] = unidad_id
    if f.sector:
        sector_id = cat.id_sector(unidad_id, f.sector)
        if sector_id is None:
            problemas.append(f"sector '{f.sector}' no existe en la unidad")
        ids["sector_id"] = sector_id
    if f.cargo:
        cargo_id = cat.id_cargo(f.cargo)
        if cargo_id is None:
            problemas.append(f"cargo '{f.cargo}' no existe")
        ids["cargo_id"] = cargo_id
    if f.turno:
        turno_id = cat.id_turno(f.turno)
        if turno_id is None:
            problemas.append(f"turno '{f.turno}' invalido (use M/T/N1/N2/N3/D o 1-6)")
        ids["turno_id"] = turno_id
    return ids, problemas


def calcular_cambios(
    filas: list[FilaPersonal],
    bd: list[dict],
    cat: Catalogos,
    bajas_global: bool = False,
) -> Cambios:
    idx = _indice_personas(bd)
    out = Cambios()
    usados: set[int] = set()
    vistas: set[tuple] = set()
    unidades_archivo: set[int] = set()
    orden_grupo: dict[tuple[int | None, int | None], int] = {}
    for p in bd:
        clave = (p.get("unidad_id"), p.get("sector_id"))
        orden_grupo[clave] = max(orden_grupo.get(clave, 0), p.get("orden") or 0)

    for f in filas:
        dup = (normalizar_nombre(f.nombre), f.ci)
        if dup in vistas:
            out.revision.append(f"L{f.linea} [{f.nombre}]: fila repetida en el archivo")
            continue
        vistas.add(dup)

        if f.ci and idx["cuenta_ci"].get(f.ci, 0) > 1:
            out.revision.append(f"L{f.linea} [{f.nombre}]: CI {f.ci} duplicada en BD")
            continue

        ids, problemas = _resolver_ids(f, cat)
        if problemas:
            sufijo = " (se crea con aplicar)" if f.unidad else ""
            out.revision.append(
                f"L{f.linea} [{f.nombre}]: {'; '.join(problemas)}{sufijo}")
            continue
        unidad_id = ids.get("unidad_id")
        if unidad_id is not None:
            unidades_archivo.add(unidad_id)

        persona = (
            idx["legacy"].get(f.id_legacy or "")
            or (idx["ci"].get(f.ci) if f.ci else None)
            or idx["nombre_unidad"].get((normalizar_nombre(f.nombre), unidad_id))
        )
        if persona is None:
            clave_g = (unidad_id, ids.get("sector_id"))
            orden_grupo[clave_g] = orden_grupo.get(clave_g, 0) + 1
            alta = {
                "nombre": f.nombre,
                "ci": f.ci or None,
                "registro": f.registro or None,
                "estado": f.estado,
                "orden": orden_grupo[clave_g],
                **ids,
            }
            if f.id_legacy:
                alta["idpersonal_legacy"] = f.id_legacy
            out.altas.append(alta)
            continue

        if persona["id"] in usados:
            out.revision.append(f"L{f.linea} [{f.nombre}]: coincide con persona ya usada")
            continue
        usados.add(persona["id"])

        # Solo se actualiza lo que el archivo trae: vacío nunca borra datos.
        nuevos = {"estado": f.estado}
        if f.ci:
            nuevos["ci"] = f.ci
        if f.registro:
            nuevos["registro"] = f.registro
        nuevos.update(ids)
        diff = {k: v for k, v in nuevos.items() if persona.get(k) != v}
        if diff:
            out.mods.append((persona["id"], diff, {k: persona.get(k) for k in diff}))

    for p in bd:
        if p.get("estado") != "ACTIVO" or p["id"] in usados:
            continue
        if not bajas_global and p.get("unidad_id") not in unidades_archivo:
            continue
        out.bajas.append((p["id"], p.get("nombre") or f"#{p['id']}"))
    return out


def calcular_ausencias(
    vac: list[tuple],
    libres: list[tuple],
    bd: list[dict],
    existentes_v: set[tuple],
    existentes_l: set[tuple],
) -> Ausencias:
    """Altas de vacaciones/libres no presentes en BD (deduplicación exacta)."""
    idx = _indice_personas(bd)
    out = Ausencias()
    vistos_v = set(existentes_v)
    vistos_l = set(existentes_l)

    def _pid(ci: str, nombre: str) -> int | None:
        p = idx["ci"].get(ci) if ci else None
        if p is None:
            p = idx["nombre"].get(normalizar_nombre(nombre))
        return p["id"] if p else None

    for ci, nombre, ini, fin, obs in vac:
        if not ini or not fin:
            out.omitidas.append(f"vacacion sin fecha valida: {nombre or ci}")
            continue
        pid = _pid(ci, nombre)
        if pid is None:
            out.omitidas.append(f"vacacion sin persona: {nombre or ci}")
            continue
        clave = (pid, ini.isoformat(), fin.isoformat())
        if clave not in vistos_v:
            vistos_v.add(clave)
            out.vacaciones.append({
                "persona_id": pid,
                "fecha_inicio": ini.isoformat(),
                "fecha_fin": fin.isoformat(),
                "observacion": obs or None,
            })

    por_persona: dict[int, list[date]] = {}
    for ci, nombre, fecha, _fin, _obs in libres:
        if not fecha:
            continue
        pid = _pid(ci, nombre)
        if pid is None:
            out.omitidas.append(f"libre sin persona: {nombre or ci}")
            continue
        por_persona.setdefault(pid, []).append(fecha)

    for pid, fechas in por_persona.items():
        unicas = sorted(set(fechas))
        inicio = fin = unicas[0]
        rangos: list[tuple[date, date]] = []
        for f in unicas[1:]:
            if f == fin + timedelta(days=1):
                fin = f
            else:
                rangos.append((inicio, fin))
                inicio = fin = f
        rangos.append((inicio, fin))
        for ini, fin_r in rangos:
            clave = (pid, ini.isoformat(), fin_r.isoformat())
            if clave not in vistos_l:
                vistos_l.add(clave)
                out.libres.append({
                    "persona_id": pid,
                    "fecha_inicio": ini.isoformat(),
                    "fecha_fin": fin_r.isoformat(),
                })
    return out


# ------------------------------------------------------------- orquestador ---

@dataclass
class Opciones:
    hoja: str = "NOMINA"
    hoja_vacaciones: str | None = None
    hoja_libres: str | None = None
    aplicar: bool = False
    solo_personal: bool = False
    bajas_global: bool = False
    sin_alta_catalogos: bool = False
    max_filas: int = MAX_FILAS_DEFECTO


@dataclass
class Informe:
    filas: int
    cambios: Cambios
    ausencias: Ausencias | None
    catalogos: dict[str, list[dict]]
    aplicado: bool
    nombres: dict[int, str] = field(default_factory=dict)

    def como_dict(self) -> dict:
        """Contrato JSON del endpoint (vista previa del panel admin)."""
        c = self.cambios
        return {
            "aplicado": self.aplicado,
            "filas": self.filas,
            "altas": [a.get("nombre") for a in c.altas],
            "mods": [
                {"id": i, "nombre": self.nombres.get(i, f"#{i}"), "campos": d, "antes": v}
                for i, d, v in c.mods
            ],
            "bajas": [{"id": i, "nombre": n} for i, n in c.bajas],
            "revision": c.revision,
            "catalogos": {
                k: [x.get("nombre", "") for x in v] for k, v in self.catalogos.items()
            },
            "ausencias": None if self.ausencias is None else {
                "vacaciones": len(self.ausencias.vacaciones),
                "libres": len(self.ausencias.libres),
                "omitidas": self.ausencias.omitidas,
            },
        }


def aplicar_cambios(cambios: Cambios, ausencias: Ausencias | None) -> None:
    """Orden conservador: modificaciones -> altas -> bajas -> ausencias."""
    for pid, diff, _viejos in cambios.mods:
        database.actualizar_filas("personas", {"id": f"eq.{pid}"}, diff)
    if cambios.altas:
        database.crear_filas("personas", cambios.altas)
    for pid, _nombre in cambios.bajas:
        database.actualizar_filas("personas", {"id": f"eq.{pid}"}, {"estado": "INACTIVO"})
    if ausencias:
        if ausencias.vacaciones:
            database.crear_filas("vacaciones", ausencias.vacaciones)
        if ausencias.libres:
            database.crear_filas("libres", ausencias.libres)


def ejecutar_importacion(datos: bytes, ops: Opciones) -> Informe:
    """Lee el .xlsx, calcula el diff y (si ops.aplicar) escribe en Supabase."""
    wb = load_workbook(io.BytesIO(datos), read_only=True, data_only=True)
    filas = leer_nomina(leer_hoja(wb, ops.hoja))
    if len(filas) > ops.max_filas:
        raise ErrorImportacion(f"{len(filas)} filas superan el limite de {ops.max_filas}")

    cat = Catalogos()
    cat.refrescar()
    catalogo_faltan = catalogos_faltantes(filas, cat)
    if ops.aplicar and not ops.sin_alta_catalogos:
        catalogo_faltan = preparar_catalogos(filas, cat)

    bd = database.obtener_personas([], [], incluir_inactivos=True)
    nombres = {p["id"]: p.get("nombre") or f"#{p['id']}" for p in bd}
    cambios = calcular_cambios(filas, bd, cat, bajas_global=ops.bajas_global)

    ausencias: Ausencias | None = None
    if not ops.solo_personal and (ops.hoja_vacaciones or ops.hoja_libres):
        vac = leer_ausencias(leer_hoja(wb, ops.hoja_vacaciones), "vacaciones") \
            if ops.hoja_vacaciones else []
        lib = leer_ausencias(leer_hoja(wb, ops.hoja_libres), "libres") \
            if ops.hoja_libres else []
        desde, hasta = RANGO_AUSENCIAS
        existentes_v = {
            (v["persona_id"], v["fecha_inicio"], v["fecha_fin"])
            for v in database.obtener_vacaciones_descargadas(desde, hasta)
        }
        existentes_l = {
            (l["persona_id"], l["fecha_inicio"], l["fecha_fin"])
            for l in database.obtener_libres_descargados(desde, hasta)
        }
        ausencias = calcular_ausencias(vac, lib, bd, existentes_v, existentes_l)

    if ops.aplicar:
        aplicar_cambios(cambios, ausencias)

    return Informe(
        filas=len(filas),
        cambios=cambios,
        ausencias=ausencias,
        catalogos=catalogo_faltan,
        aplicado=ops.aplicar,
        nombres=nombres,
    )
