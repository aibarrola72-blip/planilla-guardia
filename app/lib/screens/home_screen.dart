import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';
import '../state/app_state.dart';
import 'ausencias_screen.dart';
import 'catalogos_screen.dart';
import 'personal_list_screen.dart';
import 'plan_mensual_screen.dart';
import 'reporte_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _mostrarDialogoInvitar(BuildContext context) async {
    final estado = context.read<AppState>();
    final control = TextEditingController();
    Persona? seleccionado;
    var personas = <Persona>[];
    try {
      personas = await SupabaseService.instance.personas(incluirInactivos: true);
    } catch (_) {}
    personas = estado.personasPermitidas(personas);

    final enviar = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Invitar responsable de turno'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: control,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Responsable de turno (del personal de sus unidades):',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              DropdownButtonFormField<int?>(
                value: seleccionado?.id,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Elegir persona…'),
                items: personas.map((p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.etiqueta, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setLocal(() {
                  if (v != null) seleccionado = personas.firstWhere((p) => p.id == v);
                }),
              ),
              const SizedBox(height: 8),
              const Text(
                'Con la invitación carga Libres y Vacaciones del personal de su unidad y turno.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('enviar'),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );

    final email = control.text.trim();
    if (enviar != 'enviar' || email.isEmpty) return;

    final appState = context.read<AppState>();
    final ok = await appState.invitarRT(email, personaId: seleccionado?.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Invitación enviada a $email' : appState.error ?? 'Error al invitar'),
      ),
    );
  }

  static const _modulos = [
    (icono: Icons.group_outlined, titulo: 'Personal', ruta: PersonalListScreen()),
    (icono: Icons.settings_outlined, titulo: 'Catálogos', ruta: CatalogosScreen()),
    (icono: Icons.beach_access_outlined, titulo: 'Vacaciones', ruta: AusenciasScreen(tabla: 'vacaciones', titulo: 'Vacaciones')),
    (icono: Icons.free_cancellation_outlined, titulo: 'Libres', ruta: AusenciasScreen(tabla: 'libres', titulo: 'Libres')),
    (icono: Icons.calendar_month_outlined, titulo: 'Plan del mes', ruta: PlanMensualScreen()),
    (icono: Icons.print_outlined, titulo: 'Reporte', ruta: ReporteScreen()),
  ];

  /// El jefe gestiona su unidad: sin catálogos (los administra la supervisión).
  static const _modulosJefe = [
    (icono: Icons.group_outlined, titulo: 'Personal', ruta: PersonalListScreen()),
    (icono: Icons.beach_access_outlined, titulo: 'Vacaciones', ruta: AusenciasScreen(tabla: 'vacaciones', titulo: 'Vacaciones')),
    (icono: Icons.free_cancellation_outlined, titulo: 'Libres', ruta: AusenciasScreen(tabla: 'libres', titulo: 'Libres')),
    (icono: Icons.calendar_month_outlined, titulo: 'Plan del mes', ruta: PlanMensualScreen()),
    (icono: Icons.print_outlined, titulo: 'Reporte', ruta: ReporteScreen()),
  ];

  /// El RT solo carga libres y vacaciones.
  static const _modulosRT = [
    (icono: Icons.beach_access_outlined, titulo: 'Vacaciones', ruta: AusenciasScreen(tabla: 'vacaciones', titulo: 'Vacaciones')),
    (icono: Icons.free_cancellation_outlined, titulo: 'Libres', ruta: AusenciasScreen(tabla: 'libres', titulo: 'Libres')),
  ];

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<AppState>();
    final nombre = estado.usuario?.email ?? (estado.esJefe ? 'Jefe de Unidad' : 'Usuario');
    final modulos = estado.esRT
        ? _modulosRT
        : (estado.esJefe ? _modulosJefe : _modulos);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planilla de Guardia'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'invitar') {
                await _mostrarDialogoInvitar(context);
              } else if (v == 'salir') {
                context.read<AppState>().cerrarSesion();
              }
            },
            itemBuilder: (_) => [
              if (estado.puedeInvitar)
                PopupMenuItem(value: 'invitar', child: ListTile(leading: Icon(Icons.person_add_outlined), title: Text('Invitar personal'))),
              PopupMenuItem(value: 'salir', child: ListTile(leading: Icon(Icons.logout), title: Text('Salir'))),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hola, $nombre',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: modulos.map((m) {
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => m.ruta),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(m.icono, size: 40, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(m.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}