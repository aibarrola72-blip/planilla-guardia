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

  // 💡 Creamos el estado primero para poder enviarle el evento directamente
  final appState = AppState();

  // supabase_flutter ya observa deep links (iniciales y en vivo) por su cuenta:
  // cuando llega un enlace de recuperación emite AuthChangeEvent.passwordRecovery.
  Supabase.instance.client.auth.onAuthStateChange.listen((cambio) {
    if (cambio.event == AuthChangeEvent.passwordRecovery) {
      // 💡 En lugar de hacer un push a ciegas, le avisamos al estado global
      appState.activarModoRecuperacion();      
      
    }
  });

  runApp(ChangeNotifierProvider.value(
      value: appState..sincronizar(),
      child: const IneramApp(),
    ),
  );
}

class IneramApp extends StatelessWidget {
  const IneramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..sincronizar(),
      child: MaterialApp(
        title: 'Planilla INERAM',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF00695C),
          useMaterial3: true,
        ),
        home: const PantallaRaiz(),
      ),
    );
  }
}

class PantallaRaiz extends StatelessWidget {
  const PantallaRaiz({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<AppState>();
    // 💡 Prioridad 1: Si Supabase avisó que estamos recuperando contraseña,
    // mostramos de manera directa la pantalla correcta sin importar la sesión.
    if (estado.recuperandoContrasena) {
      return const RecuperarContrasenaScreen();
    }
    return estado.tieneSesion ? const HomeScreen() : const LoginScreen(); 
  }
}