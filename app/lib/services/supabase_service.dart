import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Servicio de acceso a datos (PostgREST vía Supabase).
///
/// Todas las llamadas usan la sesión autenticada del jefe de unidad;
/// las políticas RLS del backend permiten operar solo a usuarios con rol jefe.
class SupabaseService {
  SupabaseService._();

  static SupabaseService get instance => _inst;
  static final SupabaseService _inst = SupabaseService._();
  static final GoTrueClient _auth = Supabase.instance.client.auth;
  static final SupabaseClient _db = Supabase.instance.client;

  // ---------- Autenticación ----------

  Future<AuthResponse> iniciarSesion(String email, String password) =>
      _auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> crearUsuario(String email, String password) =>
      _auth.signUp(email: email, password: password);

  void cerrarSesion() => _auth.signOut();

  User? get usuario => _auth.currentUser;

  /// Cliente PostgREST crudo (para operaciones puntuales).
  SupabaseClient get db => _db;

  // ---------- Personal ----------

  Future<List<Persona>> personas({
    int? unidadId,
    int? sectorId,
    bool incluirInactivos = false,
  }) async {
    var query = _db.from('personas').select();

    if (!incluirInactivos) query = query.eq('estado', 'ACTIVO');
    if (sectorId != null) query = query.eq('sector_id', sectorId);
    if (unidadId != null) query = query.eq('unidad_id', unidadId);

    final datos = await query
        .order('sector_id', nullsFirst: true)
        .order('orden')
        .order('nombre');
    return datos.map((r) => Persona.fromJson(r)).toList();
  }

  Future<void> guardarPersona({int? id, required Map<String, dynamic> campos}) async {
    if (id == null) {
      await _db.from('personas').insert(campos);
    } else {
      await _db.from('personas').update(campos).eq('id', id);
    }
  }

  /// Reordena: intercambia `orden` entre dos personas del mismo grupo.
  Future<void> moverOrden(Persona a, Persona b) async {
    final paquete = [
      {'id': a.id, 'orden': b.orden},
      {'id': b.id, 'orden': a.orden},
    ];
    await _db
        .from('personas')
        .upsert(paquete, onConflict: 'id');
  }

  // ---------- Catálogos ----------

  Future<List<Unidad>> unidades() async =>
      (await _db.from('unidades').select().order('id')).map((r) => Unidad.fromJson(r)).toList();

  Future<List<Sector>> sectores() async =>
      (await _db.from('sectores').select().order('unidad_id').order('id'))
          .map((r) => Sector.fromJson(r))
          .toList();

  Future<List<Cargo>> cargos() async =>
      (await _db.from('cargos').select().order('id')).map((r) => Cargo.fromJson(r)).toList();

  Future<List<Turno>> turnos() async =>
      (await _db.from('turnos').select().order('id')).map((r) => Turno.fromJson(r)).toList();

  Future<void> crearCatalogo(String tabla, String nombre) async {
    await _db.from(tabla).insert({'nombre': nombre});
  }

  Future<void> actualizarCatalogo(String tabla, int id, Map<String, dynamic> campos) async {
    await _db.from(tabla).update(campos).eq('id', id);
  }

  // ---------- Ausencias ----------

  Future<List<AusenciaRango>> ausencias(String tabla, {int? personaId}) async {
    var query = _db.from(tabla).select();
    if (personaId != null) query = query.eq('persona_id', personaId);
    final datos = await query.order('fecha_inicio');
    return datos.map((r) => AusenciaRango.fromJson(r)).toList();
  }

  Future<void> guardarAusencia(
    String tabla, {
    int? id,
    required int personaId,
    required DateTime inicio,
    required DateTime fin,
    String? observacion,
  }) async {
    final campos = <String, dynamic>{
      'persona_id': personaId,
      'fecha_inicio': _aFechaIso(inicio),
      'fecha_fin': _aFechaIso(fin),
    };
    if (observacion != null && observacion.isNotEmpty) {
      final claveObs = tabla == 'vacaciones' ? 'observacion' : 'motivo';
      campos[claveObs] = observacion;
    }
    if (id == null) {
      await _db.from(tabla).insert(campos);
    } else {
      await _db.from(tabla).update(campos).eq('id', id);
    }
  }

  Future<void> eliminarAusencia(String tabla, int id) async {
    await _db.from(tabla).delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> planDelMes(DateTime mes) async {
    final inicio = DateTime(mes.year, mes.month, 1);
    final fin = DateTime(mes.year, mes.month + 1, 0);
    return await _db
        .from('plan_mensual')
        .select()
        .gte('fecha', inicio.toIso8601String().split('T').first)
        .lte('fecha', fin.toIso8601String().split('T').first);
  }

  /// Guarda una celda del plan (upsert por persona+fecha).
  Future<void> guardarCeldaPlan(int personaId, DateTime fecha, int turnoId) async {
    final iso = fecha.toIso8601String().split('T').first;
    await _db.from('plan_mensual').upsert(
          {
            'persona_id': personaId,
            'fecha': iso,
            'turno_id': turnoId,
          },
          onConflict: 'persona_id, fecha',
        );
  }

  Future<void> eliminarCeldaPlan(int personaId, DateTime fecha) async {
    final iso = fecha.toIso8601String().split('T').first;
    await _db.from('plan_mensual').delete().eq('persona_id', personaId).eq('fecha', iso);
  }

  /// Reemplaza por completo las celdas del plan de un mes.
  Future<void> reemplazarPlanDeMes(DateTime mes, List<Map<String, dynamic>> celdas) async {
    final inicio = DateTime(mes.year, mes.month, 1).toIso8601String().split('T').first;
    final fin = DateTime(mes.year, mes.month + 1, 0).toIso8601String().split('T').first;
    await _db.from('plan_mensual').delete().gte('fecha', inicio).lte('fecha', fin);
    if (celdas.isEmpty) return;
    await _db.from('plan_mensual').upsert(celdas, onConflict: 'persona_id, fecha');
  }
}

/// Convierte una fecha a "YYYY-MM-DD" (formato que espera PostgreSQL).
String _aFechaIso(DateTime fecha) => fecha.toIso8601String().split('T').first;