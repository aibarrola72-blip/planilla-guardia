import csv
import io
import html
import requests
import calendar
from datetime import datetime


def obtener_datos_csv_directo():
    """
    Reemplazar estas URLs por los enlaces reales de exportación CSV
    de las hojas de Google Sheets.
    """

    ID_PLANILLA = "1hGKq-jXFoAwOQvMKyIFlCLWMWUmF4q2aJVmZwg-nuU0"

    ID_PESTANA_VACACIONES = "1224886937"
    ID_PESTANA_PLANILLA = "1954202234"

    url_vacaciones = (
        f"https://docs.google.com/spreadsheets/d/"
        f"{ID_PLANILLA}/export?format=csv"
        f"&gid={ID_PESTANA_VACACIONES}"
    )

    url_planilla = (
        f"https://docs.google.com/spreadsheets/d/"
        f"{ID_PLANILLA}/export?format=csv"
        f"&gid={ID_PESTANA_PLANILLA}"
    )

    # Descargar hoja de vacaciones
    res_vac = requests.get(url_vacaciones, timeout=30)
    res_vac.raise_for_status()
    res_vac.encoding = "utf-8"

    lector_vac = csv.DictReader(io.StringIO(res_vac.text))
    datos_appsheet = list(lector_vac)

    # Descargar hoja de planilla
    res_pla = requests.get(url_planilla, timeout=30)
    res_pla.raise_for_status()
    res_pla.encoding = "utf-8"

    lector_pla = csv.reader(io.StringIO(res_pla.text))
    datos_planilla = list(lector_pla)

    return datos_appsheet, datos_planilla


def limpiar_ci(valor):
    """
    Limpia la cédula para poder cruzarla con la hoja de vacaciones.
    """
    if valor is None:
        return ""

    return (
        str(valor)
        .replace(".", "")
        .replace(",", "")
        .replace(" ", "")
        .strip()
    )


def convertir_fecha(valor):
    """
    Intenta convertir fechas provenientes de Google Sheets/AppSheet.
    Acepta formatos frecuentes.
    """
    if not valor:
        return None

    texto = str(valor).strip()

    formatos = [
        "%m/%d/%Y",
        "%d/%m/%Y",
        "%Y-%m-%d",
        "%d-%m-%Y",
        "%m-%d-%Y",
    ]

    for formato in formatos:
        try:
            return datetime.strptime(texto, formato).date()
        except ValueError:
            continue

    return None


def obtener_vacacion_activa(datos_appsheet, ci, inicio_mes, fin_mes):
    """
    Busca una vacación que se superponga con el mes solicitado.
    """

    for vacacion in datos_appsheet:
        ci_vacacion = limpiar_ci(
            vacacion.get("nroCI", "")
        )

        if ci_vacacion != ci:
            continue

        fecha_inicio = (
            vacacion.get("FECHA INICIO")
            or vacacion.get("Fecha Inicio")
            or vacacion.get("fecha_inicio")
        )

        fecha_fin = (
            vacacion.get("FECHA FIN")
            or vacacion.get("Fecha Fin")
            or vacacion.get("fecha_fin")
        )

        f_ini = convertir_fecha(fecha_inicio)
        f_fin = convertir_fecha(fecha_fin)

        if not f_ini or not f_fin:
            continue

        # No hay superposición con el mes solicitado
        if f_fin < inicio_mes or f_ini > fin_mes:
            continue

        return f_ini, f_fin

    return None


def generar_reporte_bn_automatico(anio, mes):
    datos_appsheet, datos_planilla = obtener_datos_csv_directo()

    _, total_dias = calendar.monthrange(anio, mes)

    inicio_mes = datetime(anio, mes, 1).date()
    fin_mes = datetime(anio, mes, total_dias).date()

    meses_es = [
        "ENERO",
        "FEBRERO",
        "MARZO",
        "ABRIL",
        "MAYO",
        "JUNIO",
        "JULIO",
        "AGOSTO",
        "SEPTIEMBRE",
        "OCTUBRE",
        "NOVIEMBRE",
        "DICIEMBRE",
    ]

    dias_semana_es = [
        "L",
        "M",
        "MI",
        "J",
        "V",
        "S",
        "D",
    ]

    nombre_mes = meses_es[mes - 1]

    html_reporte = f"""
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">

<title>
Planilla de Guardia - {nombre_mes} {anio}
</title>

<style>
    @page {{
        size: landscape;
        margin: 0.45cm;
    }}

    * {{
        box-sizing: border-box;
    }}

    body {{
        font-family: Arial, Helvetica, sans-serif;
        color: #000;
        background: #fff;
        margin: 0;
        padding: 0;
    }}

    .contenedor-encabezado {{
        display: flex;
        align-items: center;
        justify-content: space-between;
        width: 100%;
        margin-bottom: 8px;
    }}

    .logo-izq, .logo-der {{
        width: 65px;
        height: 65px;
        object-fit: contain;
    }}

    .encabezado {{
        text-align: center;
        flex-grow: 1;
    }}

    .encabezado .institucion {{
        font-size: 10pt;
        font-weight: bold;
        line-height: 1.25;
        margin: 0;
    }}

    .encabezado .titulo {{
        font-size: 9pt;
        font-weight: bold;
        text-decoration: underline;
        margin-top: 4px;
    }}

    .tabla-contenedor {{
        width: 100%;
        overflow: hidden;
    }}

    table {{
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
        page-break-inside: avoid;
    }}

    th,
    td {{
        border: 1px solid #000;
        text-align: center;
        vertical-align: middle;
        padding: 2px 1px;
        font-size: 6.6pt;
        line-height: 1.1;
        height: 20px;
    }}

    thead th {{
        font-weight: bold;
        background: #fff;
    }}

    .col-nombre {{
        width: 18%;
        text-align: left;
        padding-left: 4px;
    }}

    .col-categoria {{
        width: 5%;
    }}

    .col-ci {{
        width: 7%;
    }}

    .col-reg {{
        width: 6%;
    }}

    .col-horario {{
        width: 10%;
    }}

    .col-dia {{
        width: auto;
        min-width: 15px;
    }}

    .nombre {{
        text-align: left;
        white-space: nowrap;
        font-size: 6.7pt;
    }}

    .horario {{
        white-space: nowrap;
        font-size: 6.2pt;
    }}

    .dia-semana {{
        font-size: 5.8pt;
        height: 16px;
    }}

    .numero-dia {{
        font-size: 6.5pt;
        height: 17px;
    }}

    .turno {{
        font-weight: normal;
    }}

    .vacaciones {{
        font-size: 6.5pt;
        font-weight: bold;
        font-style: italic;
        text-align: center;
        vertical-align: middle;
        background-color: #fff !important;
        border: 2px solid #000 !important;
        white-space: normal;
        line-height: 1.2;
        padding: 3px;
    }}

    .observacion {{
        margin-top: 12px;
        font-size: 7pt;
        font-weight: bold;
    }}

    .firmas {{
        width: 100%;
        display: flex;
        justify-content: space-between;
        gap: 20px;
        margin-top: 42px;
        page-break-inside: avoid;
    }}

    .firma {{
        width: 32%;
        text-align: center;
        font-size: 7pt;
        padding-top: 4px;
    }}

    .linea-firma {{
        border-top: 1px solid #000;
        margin-bottom: 5px;
    }}

    .salto-pagina {{
        page-break-before: always;
    }}

    @media screen {{
        body {{
            padding: 15px;
        }}

        .tabla-contenedor {{
            overflow-x: auto;
        }}

        table {{
            min-width: 1200px;
        }}
    }}
</style>
</head>

<body>

<div class="contenedor-encabezado" style="display: flex; align-items: center; justify-content: space-between; width: 100%; font-family: sans-serif; padding: 10px 0;">
  <!-- LOGO IZQUIERDO -->
  <img src="imagen izquierda.jpg" class="logo-izq" alt="Logo MSPBS" onerror="this.style.display='none'" style="height: 75px; width: auto; object-fit: contain;">
  
  <!-- TEXTO CENTRAL -->
  <div class="encabezado-texto" style="text-align: center; flex-grow: 1; padding: 0 20px;">
    <p class="institucion" style="font-weight: bold; margin: 0 0 5px 0; font-size: 14px;">INSTITUTO NACIONAL DE ENFERMEDADES RESPIRATORIAS Y DEL AMBIENTE</p>
    <p class="institucion" style="font-weight: bold; margin: 0 0 5px 0; font-size: 14px;">INERAM - "PROF. DR. JUAN MAX BOETTNER"</p>
    <p class="titulo" style="font-weight: bold; margin: 0; font-size: 16px;">PLANILLA DE GUARDIA SALA V PEDIÁTRICA MES DE {nombre_mes} AÑO {anio}</p>
  </div>
  
  <!-- LOGO DERECHO -->
  <img src="imagen derecha.jpg" class="logo-der" alt="Logo INERAM" onerror="this.style.display='none'" style="height: 75px; width: auto; object-fit: contain;">
</div>

<div class="tabla-contenedor">
<table>
    <thead>
        <tr>
            <th rowspan="2" class="col-nombre">Nombre y Apellido</th>
            <th rowspan="2" class="col-ci">C.I. N°</th>
            <th rowspan="2" class="col-reg">Reg. N°</th>
            <th rowspan="2" class="col-horario">HORARIO</th>
"""

    # Primera fila: día de la semana
    for dia in range(1, total_dias + 1):
        fecha = datetime(anio, mes, dia)
        indice_dia = fecha.weekday()
        nombre_dia = dias_semana_es[indice_dia]

        html_reporte += (
            f'<th class="col-dia dia-semana">{nombre_dia}</th>'
        )

    html_reporte += """
        </tr>
        <tr>
"""

    # Segunda fila: número de día
    for dia in range(1, total_dias + 1):
        html_reporte += (
            f'<th class="col-dia numero-dia">{dia}</th>'
        )

    html_reporte += """
        </tr>
    </thead>
    <tbody>
"""

    # La planilla de referencia posee:
    # 0 = Nombre    
    # 1 = C.I.
    # 2 = Reg.
    # 3 = Horario
    # 4 en adelante = días del mes

    for fila in datos_planilla:
        if not fila:
            continue

        fila = [
            str(celda).strip() if celda is not None else ""
            for celda in fila
        ]
        # Ignorar filas completamente vacías
        if not any(fila):
            continue

        # Ignorar filas que no representan funcionarios
        texto_fila = " ".join(fila).upper()

        palabras_ignoradas = [
        "NOMBRE Y APELLIDO",
        "C.I. N°",
        "CI N°",
        "REG. N°",
        "HORARIO",
        "OBSERVACION",
        "OBSERVACIÓN",
        "PLANILLA DE GUARDIA",
        "FECHA INICIO",
        "FECHA FIN",
        "VACACIONES DESDE",
        "HASTA",
        "ABOG.",
        "JEFA DE SALA",
        "JEFA DEPTO.",
        "JEFE DEPTO.",
        "INSTITUTO NACIONAL DE ENFERMEDADES RESPIRATORIAS Y DEL AMBIENTE",
        "INERAM",
        "PROF. DR. JUAN MAX BOETTNER",
        ]

        if any(palabra in texto_fila for palabra in palabras_ignoradas):
            continue

        if len(fila) < 4:
            continue

        # Ignorar filas de encabezado/fecha que Google Sheets pueda devolver como datos.
        # La primera fila incorrecta del reporte comienza con una fecha (ej. 9/16/2026).
        if convertir_fecha(fila[0]) is not None:
            continue

        nombre = fila[0].strip()        
        ci = str(fila[1]).replace(".", "").replace(" ", "").strip()
        registro = fila[2].strip()
        horario = fila[3].strip()

        if not nombre:
            continue

        # Evitar filas que no parecen corresponder a personal
        if nombre.upper() in ["FECHA", "FECHAS", "DÍAS", "DIAS"]:
            continue

        html_reporte += (
            f"<tr>"
            f"<td style='text-align:left;'>{html.escape(nombre)}</td>"
            f"<td>{html.escape(ci)}</td>"
            f"<td>{html.escape(registro)}</td>"
            f"<td>{html.escape(horario)}</td>"
        )

        # Buscar vacaciones vigentes para el empleado
        vac_activa = None

        for vac in datos_appsheet:
            ci_vac = (
                str(vac.get("nroCI", ""))
                .replace(".", "")
                .replace(" ", "")
                .strip()
            )

            if ci_vac != ci:
                continue

            fecha_inicio = (
                vac.get("FECHA INICIO")
                or vac.get("Fecha Inicio")
                or vac.get("fecha_inicio")
            )

            fecha_fin = (
                vac.get("FECHA FIN")
                or vac.get("Fecha Fin")
                or vac.get("fecha_fin")
            )

            if not fecha_inicio or not fecha_fin:
                continue

            formatos_fecha = [
                "%m/%d/%Y",
                "%d/%m/%Y",
                "%Y-%m-%d",
                "%d-%m-%Y",
                "%m-%d-%Y",
            ]

            f_ini = None
            f_fin = None

            for formato in formatos_fecha:
                try:
                    f_ini = datetime.strptime(
                        str(fecha_inicio).strip(), formato
                    ).date()
                    break
                except ValueError:
                    pass

            for formato in formatos_fecha:
                try:
                    f_fin = datetime.strptime(
                        str(fecha_fin).strip(), formato
                    ).date()
                    break
                except ValueError:
                    pass

            if not f_ini or not f_fin:
                continue

            if not (f_fin < inicio_mes or f_ini > fin_mes):
                vac_activa = (f_ini, f_fin)
                break

        if vac_activa:
            f_ini, f_fin = vac_activa

            dia_inicio = max(f_ini, inicio_mes).day
            dia_fin = min(f_fin, fin_mes).day

            for dia in range(1, dia_inicio):
                indice = 3 + dia
                turno = fila[indice] if indice < len(fila) else ""
                html_reporte += f"<td>{html.escape(turno)}</td>"

            cantidad_dias_vacacion = dia_fin - dia_inicio + 1

            leyenda_vacaciones = (
                f"VACACIONES DESDE "
                f"{f_ini.strftime('%d/%m/%Y')} "
                f"HASTA "
                f"{f_fin.strftime('%d/%m/%Y')}"
            )

            html_reporte += (
                f'<td colspan="{cantidad_dias_vacacion}" '
                f'class="vacaciones">'
                f'{html.escape(leyenda_vacaciones)}'
                f'</td>'
            )

            for dia in range(dia_fin + 1, total_dias + 1):
                indice = 3 + dia
                turno = fila[indice] if indice < len(fila) else ""
                html_reporte += f"<td>{html.escape(turno)}</td>"

        else:
            for dia in range(1, total_dias + 1):
                indice = 3 + dia
                turno = fila[indice] if indice < len(fila) else ""
                html_reporte += f"<td>{html.escape(turno)}</td>"

        html_reporte += "</tr>"

    html_reporte += """
    </tbody>
</table>
</div>

<div class="observacion">
    OBSERVACIÓN: "Se aceptarán cambios de guardias con sus pares,
    la solicitud se debe realizar con 24 hs. de anticipación
    a la fecha solicitada".
</div>

<div class="firmas">
    <div class="firma">
        <div class="linea-firma"></div>
        <strong>Lic. De los Angeles Sanchez</strong><br>
        Jefa de Sala V y Urgencias Pediátricas
    </div>

    <div class="firma">
        <div class="linea-firma"></div>
        <strong>Lic. Laura Gonzalez</strong><br>
        Jefa Dpto. de Enfermería
    </div>

    <div class="firma">
        <div class="linea-firma"></div>
        <strong>Abog. Bernardino Sanabria</strong><br>
        Jefe Dpto. de Personal
    </div>
</div>

</body>
</html>
"""

    nombre_archivo = (
        f"reporte_guardias_{anio}_{mes:02d}.html"
    )

    with open(nombre_archivo, "w", encoding="utf-8") as archivo:
        archivo.write(html_reporte)

    print(
        f"Reporte generado correctamente: {nombre_archivo}"
    )


# Generar septiembre de 2026
generar_reporte_bn_automatico(2026, 9)