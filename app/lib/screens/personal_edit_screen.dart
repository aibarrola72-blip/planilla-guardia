import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/supabase_service.dart';

class PersonalEditScreen extends StatefulWidget {
  const PersonalEditScreen({
    super.key,
    this.persona,
    this.soloLectura = false,
    required this.unidades,
    required this.sectores,
    required this.cargos,
    required this.turnos,
  });

  final Persona? persona;
  final bool soloLectura;
  final List<Unidad> unidades;
  final List<Sector> sectores;
  final List<Cargo> cargos;
  final List<Turno> turnos;

  @override
  State<PersonalEditScreen> createState() => _PersonalEditScreenState();
}

class _PersonalEditScreenState extends State<PersonalEditScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _ci = TextEditingController();
  final _registro = TextEditingController();
  final _orden = TextEditingController();

  late int? _unidadId;
  late int? _sectorId;
  late int? _cargoId;
  late int? _turnoId;
  DateTime? _nocheDesde;
  String? _nocheInicioLinea;
  bool _activo = true;
  bool _guardando = false;

  bool get _turnoBaseNocturno {
    for (final t in widget.turnos) {
      if (t.id == _turnoId && ['N1', 'N2', 'N3'].contains(t.codigo)) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.persona;
    _nombre.text = p?.nombre ?? '';
    _ci.text = p?.ci ?? '';
    _registro.text = p?.registro ?? '';
    _orden.text = (p?.orden ?? 0).toString();
    _unidadId = p?.unidadId;
    _sectorId = p?.sectorId;
    _cargoId = p?.cargoId;
    _turnoId = p?.turnoId;
    _nocheDesde = p?.nocheDesde;
    _nocheInicioLinea = p?.nocheInicioLinea;
    _activo = p?.estaActivo ?? true;
  }

  Future<void> _elegirNocheDesde() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _nocheDesde ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _nocheDesde = d);
  }

  @override
  void dispose() {
    _nombre.dispose();
    _ci.dispose();
    _registro.dispose();
    _orden.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      await SupabaseService.instance.guardarPersona(
        id: widget.persona?.id,
        campos: {
          'nombre': _nombre.text.trim(),
          'ci': _ci.text.trim(),
          'registro': _registro.text.trim(),
          'unidad_id': _unidadId,
          'sector_id': _sectorId,
          'cargo_id': _cargoId,
          'turno_id': _turnoId,
          'estado': _activo ? 'ACTIVO' : 'INACTIVO',
          'orden': int.tryParse(_orden.text.trim()) ?? 0,
          'noche_desde': _turnoBaseNocturno
              ? (_nocheDesde?.toIso8601String().split('T').first)
              : null,
          'noche_inicio_linea': _turnoBaseNocturno ? _nocheInicioLinea : null,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectoresUnidad = _unidadId == null
        ? widget.sectores
        : widget.sectores.where((s) => s.unidadId == _unidadId).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.persona == null
              ? 'Nuevo personal'
              : widget.soloLectura
                  ? 'Personal (solo lectura)'
                  : 'Editar personal',
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewPadding.bottom + 24),
        child: AbsorbPointer(
          absorbing: widget.soloLectura,
          child: Form(
            key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre y apellido'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ci,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'C.I. N°'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _registro,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reg. N°'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _unidadId,
                decoration: const InputDecoration(labelText: 'Unidad'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('(sin unidad)')),
                  ...widget.unidades.map((u) => DropdownMenuItem(value: u.id, child: Text(u.nombre))),
                ],
                onChanged: (v) => setState(() {
                  _unidadId = v;
                  _sectorId = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _sectorId,
                decoration: const InputDecoration(labelText: 'Sector'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('(sin sector)')),
                  ...sectoresUnidad.map((s) => DropdownMenuItem(value: s.id, child: Text(s.nombre))),
                ],
                onChanged: (v) => setState(() => _sectorId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _cargoId,
                decoration: const InputDecoration(labelText: 'Cargo'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('(sin cargo)')),
                  ...widget.cargos.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))),
                ],
                onChanged: (v) => setState(() => _cargoId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _turnoId,
                decoration: const InputDecoration(labelText: 'Turno base'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('(sin turno)')),
                  ...widget.turnos.map(
                    (t) => DropdownMenuItem(value: t.id, child: Text('${t.codigo} · ${t.horario}')),
                  ),
                ],
                onChanged: (v) => setState(() => _turnoId = v),
              ),
              if (_turnoBaseNocturno) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inicio turno noche'),
                  subtitle: Text(
                    _nocheDesde == null
                        ? 'Sin fecha de inicio (se deriva sola)'
                        : 'Como $_nocheInicioLinea el ${DateFormat('dd/MM/yyyy').format(_nocheDesde!)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Quitar fecha',
                        onPressed: () => setState(() => _nocheDesde = null),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month),
                        tooltip: 'Elegir fecha de inicio',
                        onPressed: _elegirNocheDesde,
                      ),
                    ],
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: _nocheInicioLinea,
                  decoration: const InputDecoration(labelText: 'Línea de inicio'),
                  items: [
                    const DropdownMenuItem(value: 'N1', child: Text('N1')),
                    const DropdownMenuItem(value: 'N2', child: Text('N2')),
                    const DropdownMenuItem(value: 'N3', child: Text('N3')),
                  ],
                  onChanged: (v) => setState(() => _nocheInicioLinea = v),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _orden,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden en la planilla'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Activo'),
                subtitle: const Text('Los inactivos no aparecen en la planilla'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
              if (!widget.soloLectura) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Guardar'),
                  ),
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}