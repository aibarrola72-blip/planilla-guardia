import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';

/// Estado global de la app: sesión y carga de datos compartidos.
class AppState extends ChangeNotifier {
  AppState() {
    Supabase.instance.client.auth.onAuthStateChange.listen((estado) {

      if (estado.event == AuthChangeEvent.passwordRecovery) {
        _recuperandoContrasena = true;
      }
      _tieneSesion = estado.session != null;
      notifyListeners();
    });
  }

  bool _tieneSesion = false;
  bool get tieneSesion => _tieneSesion;

  String? _error;
  String? get error => _error;

  /// Usuario autenticado actual (o null si no hay sesión).
  User? get usuario => SupabaseService.instance.usuario;

  String? _rol;
  int? _unidadId;
  List<int> _unidades = [];
  int? _personaId;
  int? _miTurnoId;
  bool _activo = true;

  /// Rol del usuario en la planilla: 'admin', 'jefe_enfermeria', 'jefe' o 'rt'.
  String? get rol => _rol;

  /// Unidad a la que pertenece (para jefes y RT). null para los globales.
  int? get unidadId => _unidadId;

  /// Conjunto de unidades a cargo (jefes multi-unidad y RTs). vacío si global.
  List<int> get unidades => _unidades;

  /// Persona de la planilla vinculada al usuario (RT responsable de turno).
  int? get personaId => _personaId;

  /// Turno de la persona vinculada (alcance del RT). null si no aplica.
  int? get miTurnoId => _miTurnoId;

  bool get activo => _activo;

  /// admin y jefe_enfermeria operan desde la app en modo consulta.
  bool get esConsulta => _rol == 'admin' || _rol == 'jefe_enfermeria';
  bool get esJefe => _rol == 'jefe';
  bool get esRT => _rol == 'rt';
  bool get puedeInvitar => _rol == 'jefe';
  bool get puedeEditarPersonal => esJefe || esConsulta;
  bool get puedeEditarCatalogos => esConsulta;
  bool get puedeEditarPlan => esJefe;
  bool get puedeEditarAusencias => esJefe || esRT;
  bool get puedeEliminarAusencias => esJefe;

  /// Devuelve las unidades que el usuario puede operar: todas para
  /// admin/jefe_enfermeria (consulta global), solo las asignadas para jefe/RT.
  List<Unidad> unidadesPermitidas(List<Unidad> todas) {
    if (esConsulta) return todas;
    final ids = _unidades.toSet();
    return todas.where((u) => ids.contains(u.id)).toList();
  }

  /// Personas visibles para RT: solo las de sus unidades Y su turno.
  List<Persona> personasPermitidas(List<Persona> todas) {
    if (esConsulta) return todas;
    final unidades = _unidades.toSet();
    return todas
        .where((p) => unidades.contains(p.unidadId) && (miTurnoId == null || p.turnoId == miTurnoId))
        .toList();
  }

  Future<void> _cargarPerfil() async {
    final p = await SupabaseService.instance.perfil();
    _rol = p?['rol'] as String?;
    _unidadId = p?['unidad_id'] as int?;
    _unidades = (p?['unidades'] as List?)?.cast<int>().toList() ?? <int>[];
    _personaId = p?['persona_id'] as int?;
    _activo = (p?['activo'] as bool?) ?? true;
    _miTurnoId = null;
    if (_personaId != null) {
      _miTurnoId = await SupabaseService.instance.turnoDePersona(_personaId!);
    }
    notifyListeners();
  }

  bool _recuperandoContrasena = false;
  bool get recuperandoContrasena => _recuperandoContrasena;

  void activarModoRecuperacion() {
    _recuperandoContrasena = true;
    notifyListeners();
  }

  void desactivarModoRecuperacion() {
    _recuperandoContrasena = false;
    notifyListeners();
  }

  /// Fuerza una actualización del flag de sesión al iniciar.
  void sincronizar() {
    _tieneSesion = SupabaseService.instance.usuario != null;
    if (_tieneSesion) _cargarPerfil();
    notifyListeners();
  }

  Future<bool> iniciarSesion(String email, String password) async {
    _error = null;
    try {
      await SupabaseService.instance.iniciarSesion(email, password);
      _tieneSesion = true;
      await _cargarPerfil();
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Envía el correo de restablecimiento. Devuelve true si fue enviado.
  Future<bool> recuperarContrasena(String email) async {
    _error = null;
    try {
      await SupabaseService.instance.recuperarContrasena(email);
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Sin conexión: no se pudo contactar al servidor. Revisá el internet del celular ($e)';
      notifyListeners();
      return false;
    }
  }

  /// Aplica la contraseña nueva (sesión de recuperación activa).
  Future<bool> restablecerContrasena(String nueva) async {
    _error = null;
    try {
      await SupabaseService.instance.restablecerContrasena(nueva);
      _recuperandoContrasena = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Invita a un nuevo RT por correo (y lo vincula a una persona). Devuelve
  /// true si fue enviado.
  Future<bool> invitarRT(String email, {int? personaId}) async {
    _error = null;
    try {
      await SupabaseService.instance.invitarRT(email, personaId: personaId);
      return true;
    } catch (e) {
      _error = 'Error al invitar: $e';
      notifyListeners();
      return false;
    }
  }

  void cerrarSesion() {
    SupabaseService.instance.cerrarSesion();
    _tieneSesion = false;
    _recuperandoContrasena = false;
    notifyListeners();
  }
}
