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

enum _TipoCatalogo { unidades, sectores, cargos }

class _CatalogosScreenState extends State<CatalogosScreen> {
  final _svc = SupabaseService.instance;

  List<Unidad> _unidades = [];
  List<Sector> _sectores = [];
  List<Cargo> _cargos = [];
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
    ]);
    if (!mounted) return;
    setState(() {
      _unidades = resultados[0] as List<Unidad>;
      _sectores = resultados[1] as List<Sector>;
      _cargos = resultados[2] as List<Cargo>;
      _cargando = false;
    });
  }

  Future<void> _crear(_TipoCatalogo tipo) async {
    final nombre = TextEditingController();
    int? unidadId;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final esSector = tipo == _TipoCatalogo.sectores;
        return AlertDialog(
          title: Text('Nuevo ${_etiqueta(tipo)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombre,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              if (esSector) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: unidadId,
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
                final tabla = _tabla(tipo);
                if (tabla == 'sectores' && unidadId != null) {
                  await _svc.db.from('sectores').insert({'nombre': nombre.text.trim(), 'unidad_id': unidadId});
                } else {
                  await _svc.crearCatalogo(tabla, nombre.text.trim());
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _cargar();
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
      };

  String _tabla(_TipoCatalogo t) => switch (t) {
        _TipoCatalogo.unidades => 'unidades',
        _TipoCatalogo.sectores => 'sectores',
        _TipoCatalogo.cargos => 'cargos',
      };

  Future<void> _alternar(_TipoCatalogo tipo, int id, bool activo) async {
    await _svc.actualizarCatalogo(_tabla(tipo), id, {'activo': activo});
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final editar = context.watch<AppState>().puedeEditarCatalogos;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Unidades'),
              Tab(text: 'Sectores'),
              Tab(text: 'Cargos'),
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