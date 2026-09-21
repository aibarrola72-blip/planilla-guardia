/// Configuración central de la app.
///
/// Completar con los valores reales del proyecto Supabase y la URL
/// del backend de reportes antes de generar un build de producción.
class AppConfig {
  AppConfig._();

  /// URL del proyecto Supabase (Settings > API).
  static const String supabaseUrl = 'https://TU-PROYECTO.supabase.co';

  /// Clave pública (anon key) de Supabase.
  static const String supabaseAnonKey = 'TU_ANON_KEY';

  /// URL base del backend de reportes (FastAPI, p. ej. en Render/Railway).
  static const String apiReportesUrl = 'http://127.0.0.1:8000';

  /// Nombre del hospital que encabeza el reporte.
  static const String institucion = 'INSTITUTO NACIONAL DE ENFERMEDADES RESPIRATORIAS Y DEL AMBIENTE';
  static const String institucionSub = 'INERAM - "PROF. DR. JUAN MAX BOETTNER"';
}