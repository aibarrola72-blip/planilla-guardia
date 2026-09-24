import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/recuperar_contrasena_screen.dart';
import 'state/app_state.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // 💡 Única instancia del estado global; escucha por su cuenta los eventos
  // de Supabase (entre ellos passwordRecovery para el deep link).
  final appState = AppState()..sincronizar();

  runApp(ChangeNotifierProvider.value(
    value: appState,
    child: const IneramApp(),
  ));
}

class IneramApp extends StatelessWidget {
  const IneramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planilla INERAM',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00695C),
        useMaterial3: true,
      ),
      home: const PantallaRaiz(),
    );
  }
}

class PantallaRaiz extends StatelessWidget {
  const PantallaRaiz({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<AppState>();
    // 💡 Prioridad 1: si Supabase avisó que estamos recuperando contraseña,
    // mostramos la pantalla correcta sin importar la sesión.
    if (estado.recuperandoContrasena) {
      return const RecuperarContrasenaScreen();
    }
    return estado.tieneSesion ? const HomeScreen() : const LoginScreen();
  }
}