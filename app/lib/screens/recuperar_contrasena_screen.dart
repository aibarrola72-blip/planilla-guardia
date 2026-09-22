import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Pantalla mostrada al abrir el deep link de recuperación:
/// pide la contraseña nueva y la aplica a la sesión de recuperación.
class RecuperarContrasenaScreen extends StatefulWidget {
  const RecuperarContrasenaScreen({super.key});

  @override
  State<RecuperarContrasenaScreen> createState() => _RecuperarContrasenaScreenState();
}

class _RecuperarContrasenaScreenState extends State<RecuperarContrasenaScreen> {
  final _form = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _confirmar = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _nueva.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _cargando = true);
    final ok = await context
        .read<AppState>()
        .restablecerContrasena(_nueva.text);
    if (!mounted) return;
    setState(() => _cargando = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contraseña actualizada. Ya podés ingresar.')),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
      context.read<AppState>().cerrarSesion();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<AppState>().error ?? 'No se pudo actualizar la contraseña')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Elegí una contraseña nueva para tu cuenta.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nueva,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña nueva',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmar,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Repetir contraseña',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v != _nueva.text ? 'Las contraseñas no coinciden' : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _cargando ? null : _guardar,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Guardar contraseña'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}