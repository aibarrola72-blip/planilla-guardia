import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';

/// Plan mensual de turnos: matriz personal × días editables.
///
/// Las vacaciones y libres se cargan en sus módulos; aquí solo se
/// asignan turnos. El autocompletado usa el turno base con reglas
/// por defecto (todo 100% editable después).
class PlanMensualScreen extends StatefulWidget {
  const PlanMensualScreen({super.key});

  @override
  State<PlanMensualScreen> createState() => _PlanMensualScreenState();
}

class _PlanMensualScreenState extends State<PlanMensualScreen> {
  final _svc = SupabaseService.instance;
  final _meses = const ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  DateTime _mes = DateTime.now();
  bool _cargando = true;
  String? _error;

  List<Persona> _personas = [];
  List<Turno> _turnos = [];
  Map<int, String> _codigoTurno = {};
  Map<int, Turno> _turnoPorId = {};

  // clave: "personaId|fecha" -> id de turno asignado (0 = sin turno)
  Map<String, int> _celdas = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  bool get _esMesPasado {
    final ahora = DateTime.now();
    return _mes.year < ahora.year || (_mes.year == ahora.year && _mes.month < ahora.month);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait([
        _svc.personas(),
        _svc.turnos(),
        _svc.planDelMes(_mes),
      ]);
      final personas = resultados[0] as List<Persona>;
      final turnos = resultados[1] as List<Turno>;
      final plan = resultados[2] as List<Map<String, dynamic>>;

      final celdas = <String, int>{};
      for (final fila in plan) {
        final personaId = fila['persona_id'] as int;
        final fecha = (fila['fecha'] as String).split('T').first;
        final turnoId = fila['turno_id'] as int;
        celdas['$personaId|$fecha'] = turnoId;
      }

      if (!mounted) return;
      setState(() {
        _personas = personas;
        _turnos = turnos;
        _codigoTurno = {for (final t in turnos) t.id: t.codigo};
        _turnoPorId = {for (final t in turnos) t.id: t};
        _celdas = celdas;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo leer el plan: $e';
      });
    }
  }

  int get _diasDelMes => DateTime(_mes.year, _mes.month + 1, 0).day;

  String _clave(int personaId, int dia) => '$personaId|${_fecha(dia)}';

  String _fecha(int dia) => DateTime(_mes.year, _mes.month, dia).toIso8601String().split('T').first;

  /// Autocompletado base desde el turno base de cada persona.
  void _autocompletar() {
    final nuevas = <String, int>{};
    for (final p in _personas) {
      final turno = p.turnoId == null ? null : _turnoPorId[p.turnoId!];
      if (turno == null) continue;

      for (var dia = 1; dia <= _diasDelMes; dia++) {
        final fecha = DateTime(_mes.year, _mes.month, dia);
        final diaSemana = fecha.weekday; // 1=lun ... 7=dom
        final esFinSemana = diaSemana == 6 || diaSemana == 7;

        switch (turno.codigo) {
          case 'M' || 'T':
            if (!esFinSemana) nuevas[_clave(p.id, dia)] = turno.id;
          case 'D':
            if (esFinSemana) nuevas[_clave(p.id, dia)] = turno.id;
          case 'N1' || 'N2' || 'N3':
            final indice = turno.codigo.codeUnitAt(1) - 49; // 1->0, 2->1, 3->2
            if (dia % 3 == indice) nuevas[_clave(p.id, dia)] = turno.id;
        }
      }
    }
    setState(() => _celdas = nuevas);
  }

  Future<void> _guardar() async {
    setState(() => _cargando = true);
    try {
      final celdas = <Map<String, dynamic>>[];
      _celdas.forEach((clave, turnoId) {
        final partes = clave.split('|');
        celdas.add({
          'persona_id': int.parse(partes[0]),
          'fecha': partes[1],
          'turno_id': turnoId,
        });
      });
      await _svc.reemplazarPlanDeMes(_mes, celdas);
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan guardado')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  void _cambiarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta, 1));
    _cargar();
  }

  Future<void> _seleccionarTurno(int personaId, int dia) async {
    final actual = _celdas[_clave(personaId, dia)];
    final elegido = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Asignar turno', style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              title: const Text('Sin turno'),
              leading: const Icon(Icons.block),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            for (final t in _turnos)
              ListTile(
                title: Text('${t.codigo} · ${t.descripcion} · ${t.horario}'),
                leading: Icon(
                  actual == t.id ? Icons.radio_button_checked : Icons.radio_button_off,
                ),
                onTap: () => Navigator.pop(ctx, t.id),
              ),
          ],
        ),
      ),
    );
    if (elegido == null) return;
    setState(() {
      if (elegido == 0) {
        _celdas.remove(_clave(personaId, dia));
      } else {
        _celdas[_clave(personaId, dia)] = elegido;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dias = _diasDelMes;

    return Scaffold(
      appBar: AppBar(title: const Text('Plan del mes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    // Selector de mes
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => _cambiarMes(-1),
                          ),
                          Text(
                            '${_meses[_mes.month - 1]} ${_mes.year}${_esMesPasado ? '  (solo lectura)' : ''}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => _cambiarMes(1),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _autocompletar,
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Autocompletar'),
                        ),
                        FilledButton.icon(
                          onPressed: _esMesPasado ? null : _guardar,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar'),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Text(
                        'Tocá una celda para asignar el turno. Autocompletar genera '
                        'la base desde el turno de cada persona.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 4,
                          headingRowHeight: 36,
                          columns: [
                            const DataColumn(label: Text('Personal')),
                            for (var dia = 1; dia <= dias; dia++)
                              DataColumn(
                                numeric: true,
                                label: Text(
                                  '$dia',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: dia % 7 == 0 || dia % 7 == 6 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                          ],
                          rows: [
                            for (final p in _personas)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Tooltip(
                                      message: p.nombre,
                                      child: SizedBox(
                                        width: 130,
                                        child: Text(
                                          p.nombre,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (var dia = 1; dia <= dias; dia++)
                                    DataCell(
                                      InkWell(
                                        onTap: _esMesPasado ? null : () => _seleccionarTurno(p.id, dia),
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey.shade300),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            _codigoTurno[_celdas[_clave(p.id, dia)]] ?? '',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}