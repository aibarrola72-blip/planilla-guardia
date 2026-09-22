/// Configuración central de la app.
///
/// Completar con los valores reales del proyecto Supabase y la URL
/// del backend de reportes antes de generar un build de producción.
class AppConfig {
  AppConfig._();

  /// URL del proyecto Supabase (Settings > API).
  static const String supabaseUrl = 'https://oaiehscsncuyrfeqfhas.supabase.co';

  /// Clave pública (anon key) de Supabase.
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9haWVoc2NzbmN1eXJmZXFmaGFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAwMjA5MDgsImV4cCI6MjEwNTU5NjkwOH0.8IJrijsRgCUC0yYrPrTvg4DoeUxMcTYSvmP8sJpBIg8';

  /// URL base del backend de reportes (FastAPI, p. ej. en Render/Railway).
  static const String apiReportesUrl = 'https://ineram-reportes.onrender.com';

  /// Nombre del hospital que encabeza el reporte.
  static const String institucion = 'INSTITUTO NACIONAL DE ENFERMEDADES RESPIRATORIAS Y DEL AMBIENTE';
  static const String institucionSub = 'INERAM - "PROF. DR. JUAN MAX BOETTNER"';
}