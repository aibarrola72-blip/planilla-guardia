import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';
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

  Future<void> _mover(int index, List<Persona> lista) async {
    final destino = index - 1;
    if (destino >= 0) {
      await _svc.moverOrden(lista[index], lista[destino]);
      await _cargarTodo();
    }
  }

  Future<void> _bajar(int index, List<Persona> lista) async {
    final destino = index + 1;
    if (destino < lista.length) {
      await _svc.moverOrden(lista[index], lista[destino]);
      await _cargarTodo();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() {
              _incluirInactivos = !_incluirInactivos;
            }),
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
      floatingActionButton: FloatingActionButton(
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
      ),
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
                                ),
                              ),
                            );
                            _cargarTodo();
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
                              IconButton(
                                icon: const Icon(Icons.arrow_upward),
                                onPressed: () => _mover(i, _personas),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward),
                                onPressed: () => _bajar(i, _personas),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}