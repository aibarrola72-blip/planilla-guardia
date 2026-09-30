import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';
import '../state/app_state.dart';

/// Plan mensual de turnos: matriz personal × días editables.
///
/// Las vacaciones y libres se cargan en sus módulos; aquí solo se
/// asignan turnos. El autocompletado aplica la regla declarada en el
/// catálogo de turnos (turnos.regla); todo queda editable después.
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

  List<AusenciaRango> _libres = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  bool get _esMesPasado {
    final ahora = DateTime.now();
    return _mes.year < ahora.year || (_mes.year == ahora.year && _mes.month < ahora.month);
  }

  int get _diasDelMes => DateTime(_mes.year, _mes.month + 1, 0).day;

  String _clave(int personaId, int dia) => '$personaId|${_fecha(dia)}';

  String _fecha(int dia) => DateTime(_mes.year, _mes.month, dia).toIso8601String().split('T').first;

  bool _esLibre(int personaId, int dia) {
    final d = DateTime(_mes.year, _mes.month, dia);
    for (final l in _libres) {
      if (l.personaId != personaId) continue;
      if (!d.isBefore(l.inicio) && !d.isAfter(l.fin)) return true;
    }
    return false;
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
      final libres = await _svc.ausencias('libres');

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
        _libres = libres;
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

  /// Autocompletado base desde la regla del turno (turnos.regla):
  /// LABORABLE -> lun-vie, FIN_SEMANA -> sáb-dom, NOCTURNA -> rotación de
  /// 3 días anclada en personas.noche_desde, OTRO/sin turno -> se conservan
  /// las celdas existentes (no se regeneran ni se borran).
  Future<void> _autocompletar() async {
    final nuevas = <String, int>{};
    for (final p in _personas) {
      final turnoId = p.turnoId;
      final turno = turnoId == null ? null : _turnoPorId[turnoId];
      if (turno == null) {
        _conservarCeldas(p.id, nuevas);
        continue;
      }

      switch (turno.regla) {
        case 'LABORABLE':
        case 'FIN_SEMANA':
          final soloLaborables = turno.regla == 'LABORABLE';
          for (var dia = 1; dia <= _diasDelMes; dia++) {
            if (_esLibre(p.id, dia)) continue;
            final fecha = DateTime(_mes.year, _mes.month, dia);
            final esFinSemana = fecha.weekday == 6 || fecha.weekday == 7;
            if (soloLaborables ? !esFinSemana : esFinSemana) {
              nuevas[_clave(p.id, dia)] = turno.id;
            }
          }
          break;

        case 'NOCTURNA':
          final baseIdx = turno.offsetNocturna;
          final off = _offsetDeLinea(p.nocheInicioLinea);
          final desde = p.nocheDesde;
          if (baseIdx == null || off == null || desde == null) {
            _conservarCeldas(p.id, nuevas);
            break;
          }
          for (var dia = 1; dia <= _diasDelMes; dia++) {
            if (_esLibre(p.id, dia)) continue;
            final diff = DateTime.utc(_mes.year, _mes.month, dia)
                .difference(DateTime.utc(desde.year, desde.month, desde.day))
                .inDays;
            final indice = ((off + diff) % 3 + 3) % 3;
            if (indice == baseIdx) nuevas[_clave(p.id, dia)] = turno.id;
          }
          break;

        default: // 'OTRO' o regla desconocida: solo asignación manual
          _conservarCeldas(p.id, nuevas);
      }
    }
    setState(() => _celdas = nuevas);
  }

  /// Offset de la rotación nocturna para una línea (codigo de turno).
  int? _offsetDeLinea(String? codigo) {
    if (codigo == null) return null;
    for (final t in _turnos) {
      if (t.codigo == codigo) return t.offsetNocturna;
    }
    const legado = {'N1': 0, 'N2': 1, 'N3': 2};
    return legado[codigo];
  }

  void _conservarCeldas(int personaId, Map<String, int> destino) {
    final prefijo = '$personaId|';
    _celdas.forEach((clave, turnoId) {
      if (clave.startsWith(prefijo)) destino[clave] = turnoId;
    });
  }

  Future<void> _guardar() async {
    setState(() => _cargando = true);
    try {
      final celdasGuardar = <Map<String, dynamic>>[];
      _celdas.forEach((clave, turnoId) {
        final partes = clave.split('|');
        celdasGuardar.add({
          'persona_id': int.parse(partes[0]),
          'fecha': partes[1],
          'turno_id': turnoId,
        });
      });
      await _svc.reemplazarPlanDeMes(_mes, celdasGuardar);
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
        child: SingleChildScrollView(
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
    final editar = context.watch<AppState>().puedeEditarPlan;

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
                            '${_meses[_mes.month - 1]} ${_mes.year}${(!editar || _esMesPasado) ? '  (solo lectura)' : ''}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => _cambiarMes(1),
                          ),
                        ],
                      ),
                    ),
                    if (editar)
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
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Tocá una celda para asignar el turno. Autocompletar genera '
                        'la base desde el turno de cada persona.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: _TablaPlan(
                        dias: dias,
                        mes: _mes,
                        permitirEdicion: editar,
                        personas: _personas,
                        celdas: _celdas,
                        codigoTurno: _codigoTurno,
                        esMesPasado: _esMesPasado,
                        esLibre: _esLibre,
                        clave: _clave,
                        onTapCelda: _seleccionarTurno,
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Tabla del plan mensual con la columna "Personal" y la fila de días
/// fijas (pinned) mientras el resto se desplaza — así siempre sabés qué
/// día y qué persona estás mirando.
class _TablaPlan extends StatelessWidget {
  const _TablaPlan({
    required this.dias,
    required this.mes,
    required this.permitirEdicion,
    required this.personas,
    required this.celdas,
    required this.codigoTurno,
    required this.esMesPasado,
    required this.esLibre,
    required this.clave,
    required this.onTapCelda,
  });

  final int dias;
  final DateTime mes;
  final bool permitirEdicion;
  final List<Persona> personas;
  final Map<String, int> celdas;
  final Map<int, String> codigoTurno;
  final bool esMesPasado;
  final bool Function(int, int) esLibre;
  final String Function(int, int) clave;
  final void Function(int, int) onTapCelda;

  static const _anchoPersonal = 160.0;
  static const _anchoDia = 36.0;
  static const _alto = 40.0;
  static const _altoCabecera = 36.0;

  bool _esFinDeSemana(int dia) {
    final w = DateTime(mes.year, mes.month, dia).weekday;
    return w == 6 || w == 7;
  }

  @override
  Widget build(BuildContext context) {
    return TableView.builder(
      columnCount: dias + 1, // +1 = columna Personal
      rowCount: personas.length + 1, // +1 = fila de días
      pinnedRowCount: 1,
      pinnedColumnCount: 1,
      columnBuilder: (index) => TableSpan(
        extent: FixedTableSpanExtent(index == 0 ? _anchoPersonal : _anchoDia),
      ),
      rowBuilder: (index) => TableSpan(
        extent: FixedTableSpanExtent(index == 0 ? _altoCabecera : _alto),
      ),
      cellBuilder: (context, position) {
        final esCabecera = position.row == 0;
        final esPersonal = position.column == 0;

        if (esCabecera && esPersonal) {
          return const TableViewCell(
            child: Center(
              child: Text(
                'Personal',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        if (esCabecera) {
          final dia = position.column;
          return TableViewCell(
            child: Center(
              child: Text(
                '$dia',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: _esFinDeSemana(dia) ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }

        final persona = personas[position.row - 1];

        if (esPersonal) {
          return TableViewCell(
            child: Tooltip(
              message: persona.nombre,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    persona.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          );
        }

        final dia = position.column;
        final esLibreDia = esLibre(persona.id, dia);
        final turnoId = celdas[clave(persona.id, dia)];
        final codigo = turnoId != null ? codigoTurno[turnoId] : null;
        final editable = permitirEdicion && !esMesPasado && !esLibreDia;

        return TableViewCell(
          child: InkWell(
            onTap: editable ? () => onTapCelda(persona.id, dia) : null,
            child: Container(
              height: _alto,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: esLibreDia ? Colors.amber.shade100 : null,
                border: Border.all(
                  color: esLibreDia ? Colors.amber : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                esLibreDia
                    ? 'L'
                    : (codigo ?? ''),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: esLibreDia ? Colors.brown.shade700 : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
