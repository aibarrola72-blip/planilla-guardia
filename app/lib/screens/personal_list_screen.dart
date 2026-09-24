import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';
import '../state/app_state.dart';
import 'personal_edit_screen.dart';

class PersonalListScreen extends StatefulWidget {
  const PersonalListScreen({super.key});

  @override
  State<PersonalListScreen> createState() => _PersonalListScreenState();
}

class _PersonalListScreenState extends State<PersonalListScreen> {
  final _svc = SupabaseService.instance;

  bool _cargando = true;
  bool _incluirInactivos = false;
  String? _error;

  List<Persona> _personas = [];
  List<Unidad> _unidades = [];
  List<Sector> _sectores = [];
  List<Cargo> _cargos = [];
  List<Turno> _turnos = [];
  Map<int, String> _cargoNombre = {};
  int? _unidadFiltro;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final personas = await _svc.personas(
        unidadId: _unidadFiltro,
        incluirInactivos: _incluirInactivos,
      );
      final unidades = await _svc.unidades();
      final sectores = await _svc.sectores();
      final cargos = await _svc.cargos();
      final turnos = await _svc.turnos();

      if (!mounted) return;
      setState(() {
        _personas = personas;
        _unidades = unidades;
        _sectores = sectores;
        _cargos = cargos;
        _turnos = turnos;
        _cargoNombre = {for (final c in cargos) c.id: c.nombre};
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo leer el personal: $e';
      });
    }
  }

  static const _grupoTurno = {'M': 0, 'T': 1, 'N1': 2, 'N2': 3, 'N3': 4, 'D': 5};

  int _grupo(Persona p) => _grupoTurno[p.turnoCodigo] ?? 6;

  bool _mismoGrupo(Persona a, Persona b) =>
      _grupo(a) == _grupo(b) && (a.unidadId ?? 0) == (b.unidadId ?? 0);

  Future<void> _subir(int index) async {
    if (index <= 0) return;
    await _moverYRenumerar(index, index - 1);
  }

  Future<void> _bajar(int index) async {
    if (index >= _personas.length - 1) return;
    await _moverYRenumerar(index, index + 1);
  }

  Future<void> _moverYRenumerar(int origen, int destino) async {
    if (!_mismoGrupo(_personas[origen], _personas[destino])) return;
    final lista = List.of(_personas);
    final item = lista.removeAt(origen);
    lista.insert(destino, item);
    try {
      await _svc.renumerarOrden(lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo reordenar')));
      }
      return;
    }
    await _cargarTodo();
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<AppState>();
    final editar = estado.puedeEditarPersonal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              setState(() => _incluirInactivos = !_incluirInactivos);
              _cargarTodo();
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'toggle',
                checked: _incluirInactivos,
                child: const Text('Mostrar inactivos'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Todos'),
                    selected: _unidadFiltro == null,
                    onSelected: (_) => setState(() {
                      _unidadFiltro = null;
                      _cargarTodo();
                    }),
                  ),
                ),
                for (final u in _unidades)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(u.nombre),
                      selected: _unidadFiltro == u.id,
                      onSelected: (_) => setState(() {
                        _unidadFiltro = u.id;
                        _cargarTodo();
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: editar
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PersonalEditScreen(
                      unidades: _unidades,
                      sectores: _sectores,
                      cargos: _cargos,
                      turnos: _turnos,
                    ),
                  ),
                );
                _cargarTodo();
              },
              tooltip: 'Agregar personal',
              child: const Icon(Icons.add),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _personas.isEmpty
                  ? const Center(child: Text('Sin personal cargado.'))
                  : ListView.separated(
                      itemCount: _personas.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = _personas[i];
                        final cargo = _cargoNombre[p.cargoId] ?? '';
                        return ListTile(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PersonalEditScreen(
                                  persona: p,
                                  unidades: _unidades,
                                  sectores: _sectores,
                                  cargos: _cargos,
                                  turnos: _turnos,
                                  soloLectura: !editar,
                                ),
                              ),
                            );
                            if (editar) _cargarTodo();
                          },
                          leading: Text(
                            '${p.orden}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          title: Text(p.nombre),
                          subtitle: Text(
                            'CI ${p.ci} · Reg ${p.registro}${cargo.isEmpty ? '' : ' · $cargo'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!p.estaActivo)
                                const Chip(
                                  label: Text('INACTIVO'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (editar) ...[
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward),
                                  onPressed: () => _subir(i),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_downward),
                                  onPressed: () => _bajar(i),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}