import 'package:app_links/app_links.dart';
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

  final appLinks = AppLinks();

  // Deep link inicial (correo de recuperación tocado con la app cerrada).
  final uri = await appLinks.getInitialLink();
  if (uri != null) {
    _procesarDeepLink(uri);
  }

  // Deep links en vivo (app ya abierta).
  appLinks.uriLinkStream.listen(_procesarDeepLink);

  runApp(const IneramApp());
  escucharRecuperacion();
}

void _procesarDeepLink(Uri uri) {
  try {
    Supabase.instance.handleDeepLink(uri);
  } catch (_) {
    // Link inválido o no relacionado con login: se ignora.
  }
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
    return estado.tieneSesion ? const HomeScreen() : const LoginScreen();
  }
}

/// Escucha el evento "recovery" de Supabase: llegó un deep link de
/// restablecimiento de contraseña. Muestra la pantalla para la contraseña nueva.
void escucharRecuperacion() {
  Supabase.instance.client.auth.onAuthStateChange.listen((cambio) {
    if (cambio.event == AuthChangeEvent.recovery) {
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => const RecuperarContrasenaScreen(),
        ),
      );
    }
  });
}