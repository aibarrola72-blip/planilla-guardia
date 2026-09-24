import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';
import '../state/app_state.dart';

/// Administración de unidades, sectores y cargos (catálogos creables).
class CatalogosScreen extends StatefulWidget {
  const CatalogosScreen({super.key});

  @override
  State<CatalogosScreen> createState() => _CatalogosScreenState();
}

enum _TipoCatalogo { unidades, sectores, cargos, turnos }

class _CatalogosScreenState extends State<CatalogosScreen> {
  final _svc = SupabaseService.instance;

  List<Unidad> _unidades = [];
  List<Sector> _sectores = [];
  List<Cargo> _cargos = [];
  List<Turno> _turnos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final resultados = await Future.wait([
      _svc.unidades(),
      _svc.sectores(),
      _svc.cargos(),
      _svc.turnos(),
    ]);
    if (!mounted) return;
    setState(() {
      _unidades = resultados[0] as List<Unidad>;
      _sectores = resultados[1] as List<Sector>;
      _cargos = resultados[2] as List<Cargo>;
      _turnos = resultados[3] as List<Turno>;
      _cargando = false;
    });
  }

  Future<void> _crear(_TipoCatalogo tipo) async {
    final nombre = TextEditingController();
    final codigo = TextEditingController();
    final descripcion = TextEditingController();
    final horaInicio = TextEditingController();
    final horaFin = TextEditingController();
    int? unidadId;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final esSector = tipo == _TipoCatalogo.sectores;
        final esTurno = tipo == _TipoCatalogo.turnos;
        return AlertDialog(
          title: Text('Nuevo ${_etiqueta(tipo)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (esTurno)
                TextField(
                  controller: codigo,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Código (ej. M, T, D, N1…)'),
                )
              else
                TextField(
                  controller: nombre,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
              if (esTurno) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: descripcion,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: horaInicio,
                  decoration: const InputDecoration(labelText: 'Hora inicio (ej. 07:00)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: horaFin,
                  decoration: const InputDecoration(labelText: 'Hora fin (ej. 13:00)'),
                ),
              ],
              if (esSector) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: unidadId,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: _unidades
                      .map((u) => DropdownMenuItem(value: u.id, child: Text(u.nombre)))
                      .toList(),
                  onChanged: (v) => unidadId = v,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  if (esTurno) {
                    await _svc.db.from('turnos').insert({
                      'codigo': codigo.text.trim(),
                      'descripcion': descripcion.text.trim(),
                      'hora_inicio': horaInicio.text.trim(),
                      'hora_fin': horaFin.text.trim(),
                    });
                  } else if (esSector && unidadId != null) {
                    await _svc.db.from('sectores').insert({'nombre': nombre.text.trim(), 'unidad_id': unidadId});
                  } else {
                    await _svc.crearCatalogo(_tabla(tipo), nombre.text.trim());
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _cargar();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error al crear: $e')));
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  String _etiqueta(_TipoCatalogo t) => switch (t) {
        _TipoCatalogo.unidades => 'unidad',
        _TipoCatalogo.sectores => 'sector',
        _TipoCatalogo.cargos => 'cargo',
        _TipoCatalogo.turnos => 'turno',
      };

  String _tabla(_TipoCatalogo t) => switch (t) {
        _TipoCatalogo.unidades => 'unidades',
        _TipoCatalogo.sectores => 'sectores',
        _TipoCatalogo.cargos => 'cargos',
        _TipoCatalogo.turnos => 'turnos',
      };

  Future<void> _alternar(_TipoCatalogo tipo, int id, bool activo) async {
    await _svc.actualizarCatalogo(_tabla(tipo), id, {'activo': activo});
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final editar = context.watch<AppState>().puedeEditarCatalogos;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Unidades'),
              Tab(text: 'Sectores'),
              Tab(text: 'Cargos'),
              Tab(text: 'Turnos'),
            ],
          ),
        ),
        floatingActionButton: editar
            ? FloatingActionButton(
                onPressed: () {
                  final tab = DefaultTabController.of(context).index;
                  _crear(_TipoCatalogo.values[tab]);
                },
                child: const Icon(Icons.add),
              )
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _listado(
                    _TipoCatalogo.unidades,
                    [for (final u in _unidades) (u.id, u.nombre, u.activo)],
                    editable: editar,
                  ),
                  _listado(
                    _TipoCatalogo.sectores,
                    [
                      for (final s in _sectores)
                        (
                          s.id,
                          '${_nombreUnidad(s.unidadId)} · ${s.nombre}',
                          s.activo,
                        ),
                    ],
                    editable: editar,
                  ),
                  _listado(
                    _TipoCatalogo.cargos,
                    [for (final c in _cargos) (c.id, c.nombre, c.activo)],
                    editable: editar,
                  ),
                  _listado(
                    _TipoCatalogo.turnos,
                    [
                      for (final t in _turnos)
                        (t.id, '${t.codigo} · ${t.descripcion}${t.horario.isEmpty ? '' : ' · ${t.horario}'}', t.activo),
                    ],
                    editable: editar,
                  ),
                ],
              ),
      ),
    );
  }

  String _nombreUnidad(int? id) {
    if (id == null) return '(sin unidad)';
    return _unidades.firstWhere((u) => u.id == id, orElse: () => Unidad(id: id, nombre: '?', activo: true)).nombre;
  }

  Widget _listado(_TipoCatalogo tipo, List<(int, String, bool)> items, {bool editable = true}) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final (id, nombre, activo) = items[i];
        return ListTile(
          title: Text(nombre),
          trailing: Switch(
            value: activo,
            onChanged: editable ? (v) => _alternar(tipo, id, v) : null,
          ),
        );
      },
    );
  }
}