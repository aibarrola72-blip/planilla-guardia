import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ausencias_screen.dart';
import 'catalogos_screen.dart';
import 'personal_list_screen.dart';
import 'plan_mensual_screen.dart';
import 'reporte_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _modulos = [
    (icono: Icons.group_outlined, titulo: 'Personal', ruta: PersonalListScreen()),
    (icono: Icons.settings_outlined, titulo: 'Catálogos', ruta: CatalogosScreen()),
    (icono: Icons.beach_access_outlined, titulo: 'Vacaciones', ruta: AusenciasScreen(tabla: 'vacaciones', titulo: 'Vacaciones')),
    (icono: Icons.free_cancellation_outlined, titulo: 'Libres', ruta: AusenciasScreen(tabla: 'libres', titulo: 'Libres')),
    (icono: Icons.calendar_month_outlined, titulo: 'Plan del mes', ruta: PlanMensualScreen()),
    (icono: Icons.print_outlined, titulo: 'Reporte', ruta: ReporteScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<AppState>();
    final nombre = estado.usuario?.email ?? 'Jefe de Unidad';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planilla de Guardia'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'salir') context.read<AppState>().cerrarSesion();
            },
            itemBuilder: (_) => const [
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
                children: _modulos.map((m) {
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