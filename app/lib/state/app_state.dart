import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  final bool _listo = false;
  bool get listo => _listo;

  String? _error;
  String? get error => _error;

  /// Usuario autenticado actual (o null si no hay sesión).
  User? get usuario => SupabaseService.instance.usuario;

  String? _rol;
  int? _unidadId;
  bool _activo = true;

  /// Rol del usuario en la planilla: 'admin', 'jefe_enfermeria', 'jefe' o 'rt'.
  String? get rol => _rol;

  /// Unidad a la que pertenece (para jefes y RT). null para los globales.
  int? get unidadId => _unidadId;

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

  Future<void> _cargarPerfil() async {
    final p = await SupabaseService.instance.perfil();
    _rol = p?['rol'] as String?;
    _unidadId = p?['unidad_id'] as int?;
    _activo = (p?['activo'] as bool?) ?? true;
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

  /// Invita a un nuevo RT por correo. Devuelve true si fue enviado.
  Future<bool> invitarRT(String email) async {
    _error = null;
    try {
      await SupabaseService.instance.invitarRT(email);
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
