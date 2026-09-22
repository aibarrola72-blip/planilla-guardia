import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Estado global de la app: sesión y carga de datos compartidos.
class AppState extends ChangeNotifier {
  AppState() {
    Supabase.instance.client.auth.onAuthStateChange.listen((estado) {
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

  /// Fuerza una actualización del flag de sesión al iniciar.
  void sincronizar() {
    _tieneSesion = SupabaseService.instance.usuario != null;
    notifyListeners();
  }

  Future<bool> iniciarSesion(String email, String password) async {
    _error = null;
    try {
      await SupabaseService.instance.iniciarSesion(email, password);
      _tieneSesion = true;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> crearCuenta(String email, String password) async {
    _error = null;
    try {
      await SupabaseService.instance.crearUsuario(email, password);
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
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Invita a un nuevo jefe por correo. Devuelve true si fue enviado.
  Future<bool> invitarJefe(String email) async {
    _error = null;
    try {
      await SupabaseService.instance.invitarJefe(email);
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
    notifyListeners();
  }
}
