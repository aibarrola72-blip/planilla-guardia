"""CLI de la importación masiva de personal desde Excel (dry-run por defecto).

El núcleo vive en backend/app/importar_personas.py (mismo código que usa el
panel admin en POST /api/admin/importar-personas).

Uso:
  python importar_excel.py listado.xlsx                    # dry-run (default)
  python importar_excel.py listado.xlsx --aplicar
  python importar_excel.py listado.xlsx --aplicar --hoja-vacaciones V --hoja-libres L
  python importar_excel.py listado.xlsx --solo-personal
  python importar_excel.py listado.xlsx --aplicar --bajas-global

Requiere SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY (backend/.env o entorno).
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from dotenv import load_dotenv  # noqa: E402

from app import importar_personas as ip  # noqa: E402

load_dotenv(ROOT / "backend" / ".env")

TOPE_LISTA = 30


def _lista(titulo: str, items: list[str]) -> None:
    print(f"{titulo} {len(items)}")
    for x in items[:TOPE_LISTA]:
        print(f"   {x}")
    if len(items) > TOPE_LISTA:
        print(f"   ... y {len(items) - TOPE_LISTA} mas")


def _reporte(informe: ip.Informe) -> None:
    c = informe.cambios
    print("\n=== REPORTE ===")
    print(f"filas leidas ............ {informe.filas}")
    _lista("altas nuevas ............",
           [f"+ {a.get('nombre')} (unidad {a.get('unidad_id')})" for a in c.altas])
    _lista("modificaciones ..........",
           [f"~ {informe.nombres.get(i, f'#{i}')}: "
            + ", ".join(f"{k} {v.get(k)} -> {n}" for k, n in v.items())
            for i, n, v in c.mods])
    _lista("bajas (INACTIVO) ........", [f"- {n}" for _i, n in c.bajas])
    _lista("filas a revision ........", [f"! {r}" for r in c.revision])
    for tabla, items in informe.catalogos.items():
        if items:
            print(f"catalogos a crear [{tabla}] {len(items)}: "
                  + ", ".join(i.get("nombre", "") for i in items))
    if informe.ausencias is not None:
        print(f"vacaciones nuevas ....... {len(informe.ausencias.vacaciones)}")
        print(f"libres nuevos (rangos) .. {len(informe.ausencias.libres)}")
        if informe.ausencias.omitidas:
            _lista("ausencias omitidas ......", [f"! {o}" for o in informe.ausencias.omitidas])
    if informe.aplicado:
        print("\nAPLICADO en Supabase.")
    else:
        print("\nDRY-RUN: no se escribio nada. Repite con --aplicar para confirmar.")


def main() -> None:
    p = argparse.ArgumentParser(description="Importacion masiva de personal desde Excel (NOMINA).")
    p.add_argument("archivo", help="Libro .xlsx")
    p.add_argument("--hoja", default="NOMINA", help="Hoja del personal (default: NOMINA)")
    p.add_argument("--hoja-vacaciones", help="Hoja de vacaciones (opcional)")
    p.add_argument("--hoja-libres", help="Hoja de libres (opcional)")
    p.add_argument("--aplicar", action="store_true", help="Escribe en BD (default: dry-run)")
    p.add_argument("--solo-personal", action="store_true", help="Ignora hojas de ausencias")
    p.add_argument("--bajas-global", action="store_true",
                   help="Baja tambien personal de unidades no tocadas por el archivo")
    p.add_argument("--sin-alta-catalogos", action="store_true",
                   help="No crea unidades/sectores/cargos faltantes")
    args = p.parse_args()

    faltantes = {"SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"} - set(os.environ)
    if faltantes:
        raise SystemExit(f"Faltan variables de entorno: {faltantes}")

    ruta = Path(args.archivo)
    if not ruta.exists():
        raise SystemExit(f"No existe el archivo: {ruta}")

    try:
        informe = ip.ejecutar_importacion(ruta.read_bytes(), ip.Opciones(
            hoja=args.hoja,
            hoja_vacaciones=args.hoja_vacaciones,
            hoja_libres=args.hoja_libres,
            aplicar=args.aplicar,
            solo_personal=args.solo_personal,
            bajas_global=args.bajas_global,
            sin_alta_catalogos=args.sin_alta_catalogos,
        ))
    except ip.ErrorImportacion as exc:
        raise SystemExit(f"[error] {exc}")

    _reporte(informe)


if __name__ == "__main__":
    main()
