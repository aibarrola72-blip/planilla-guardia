import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';

/// Pantalla parametrizada para administrar rangos de ausencia.
/// - `tabla`: 'vacaciones' o 'libres'
class AusenciasScreen extends StatefulWidget {
  const AusenciasScreen({super.key, required this.tabla, required this.titulo});

  final String tabla;
  final String titulo;

  @override
  State<AusenciasScreen> createState() => _AusenciasScreenState();
}

class _AusenciasScreenState extends State<AusenciasScreen> {
  final _svc = SupabaseService.instance;
  final _fmt = DateFormat('dd/MM/yyyy');
  final _buscar = SearchController();

  bool _cargando = true;
  String? _error;
  List<AusenciaRango> _ausencias = [];
  List<Persona> _personas = [];

  bool get _esLibre => widget.tabla == 'libres';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait([
        _svc.ausencias(widget.tabla),
        _svc.personas(incluirInactivos: true),
      ]);
      if (!mounted) return;
      setState(() {
        _ausencias = resultados[0] as List<AusenciaRango>;
        _personas = resultados[1] as List<Persona>;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron leer las ausencias: $e';
      });
    }
  }

  String _nombrePersona(int id) => _personas
      .firstWhere((p) => p.id == id, orElse: () => Persona(id: id, nombre: 'ID $id', ci: '', registro: '', estado: 'ACTIVO', orden: 0))
      .nombre;

  Future<void> _agregar() async {
    int? personaId;
    Persona? seleccionado;
    DateTime fecha = DateTime.now();
    DateTime? hasta;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(_esLibre ? 'Nuevo día libre' : 'Nuevo periodo de vacaciones'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SearchAnchor(
                    searchController: _buscar,
                    builder: (bctx, controller) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(seleccionado?.nombre ?? 'Seleccionar personal'),
                      subtitle: seleccionado == null
                          ? const Text('Tocá y escribí para filtrar por nombre o CI…')
                          : Text('CI ${seleccionado!.ci}'),
                      trailing: const Icon(Icons.search),
                      onTap: () => controller.openView(),
                    ),
                    suggestionsBuilder: (sctx, controller) {
                      final q = controller.text.trim().toLowerCase();
                      final filtrados = _personas
                          .where((p) =>
                              q.isEmpty ||
                              p.nombre.toLowerCase().contains(q) ||
                              (p.ci.isNotEmpty && p.ci.contains(q)))
                          .toList();
                      return [
                        for (final p in filtrados)
                          ListTile(
                            title: Text(p.nombre),
                            subtitle: Text('CI ${p.ci}'),
                            trailing: p.id == personaId ? const Icon(Icons.check) : null,
                            onTap: () {
                              controller.closeView(p.nombre);
                              setLocal(() {
                                personaId = p.id;
                                seleccionado = p;
                              });
                            },
                          ),
                      ];
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_esLibre) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Día libre'),
                      subtitle: Text(_fmt.format(fecha)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final d = await _elegirDia(ctx, fecha);
                        if (d != null) setLocal(() => fecha = d);
                      },
                    ),
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Desde'),
                      subtitle: Text(_fmt.format(fecha)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final d = await _elegirDia(ctx, fecha);
                        if (d != null) setLocal(() => fecha = d);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hasta'),
                      subtitle: Text(_fmt.format(hasta ?? fecha)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final d = await _elegirDia(ctx, hasta ?? fecha);
                        if (d != null) setLocal(() => hasta = d);
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: () async {
                    final fin = _esLibre ? fecha : (hasta ?? fecha);
                    if (personaId == null || fin.isBefore(fecha)) return;
                    await _svc.guardarAusencia(
                      widget.tabla,
                      personaId: personaId!,
                      inicio: fecha,
                      fin: fin,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _cargar();
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<DateTime?> _elegirDia(BuildContext ctx, DateTime inicial) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    return d;
  }

  Future<void> _eliminar(AusenciaRango r) async {
    await _svc.eliminarAusencia(widget.tabla, r.id);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregar,
        tooltip: 'Agregar',
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _ausencias.isEmpty
                  ? const Center(child: Text('Sin registros.'))
                  : ListView.separated(
                      itemCount: _ausencias.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final a = _ausencias[i];
                        return ListTile(
                          title: Text(_nombrePersona(a.personaId)),
                          subtitle: Text(
                            a.inicio == a.fin
                                ? _fmt.format(a.inicio)
                                : '${_fmt.format(a.inicio)} → ${_fmt.format(a.fin)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _eliminar(a),
                          ),
                        );
                      },
                    ),
    );
  }
}