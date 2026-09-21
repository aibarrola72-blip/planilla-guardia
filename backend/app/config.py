import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

ASSETS_DIR = os.path.join(os.path.dirname(__file__), "..", "assets")
TEMPLATES_DIR = os.path.join(os.path.dirname(__file__), "..", "templates")

INSTITUCION = "INSTITUTO NACIONAL DE ENFERMEDADES RESPIRATORIAS Y DEL AMBIENTE"
INSTITUCION_SUB = 'INERAM - "PROF. DR. JUAN MAX BOETTNER"'

OBSERVACION = (
    'OBSERVACIÓN: "Se aceptarán cambios de guardias con sus pares, '
    "la solicitud se debe realizar con 24 hs. de anticipación "
    'a la fecha solicitada".'
)

# Lista de firmas que aparece al pie del reporte.
FIRMAS = [
    ("Lic. De los Angeles Sanchez", "Jefa de Sala V y Urgencias Pediátricas"),
    ("Lic. Laura Gonzalez", "Jefa Dpto. de Enfermería"),
    ("Abog. Bernardino Sanabria", "Jefe Dpto. de Personal"),
]

MESES_ES = [
    "ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO",
    "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE",
]

DIAS_SEMANA_ES = ["L", "M", "MI", "J", "V", "S", "D"]