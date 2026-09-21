import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

/// Genera y comparte el PDF mensual de guardia desde el backend de reportes.
class ReporteScreen extends StatefulWidget {
  const ReporteScreen({super.key});

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen> {
  final _svc = SupabaseService.instance;
  final _meses = const ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  int _anio = DateTime.now().year;
  int _mes = DateTime.now().month;
  int? _unidadId;
  int? _sectorId;

  List<Unidad> _unidades = [];
  List<Sector> _sectores = [];
  bool _cargandoCat = true;
  bool _generando = false;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  Future<void> _cargarCatalogos() async {
    final r = await Future.wait([_svc.unidades(), _svc.sectores()]);
    if (!mounted) return;
    setState(() {
      _unidades = r[0] as List<Unidad>;
      _sectores = r[1] as List<Sector>;
      _cargandoCat = false;
    });
  }

  List<Sector> get _sectoresUnidad =>
      _unidadId == null ? _sectores : _sectores.where((s) => s.unidadId == _unidadId).toList();

  Future<void> _generar() async {
    setState(() {
      _generando = true;
      _mensaje = null;
    });
    try {
      final url = Uri.parse('${AppConfig.apiReportesUrl}/api/reporte/mensual');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'anio': _anio,
          'mes': _mes,
          'unidad_ids': [_unidadId].whereType<int>().toList(),
          'sector_ids': [_sectorId].whereType<int>().toList(),
          'formato': 'pdf',
        }),
      ).timeout(const Duration(seconds: 90));

      if (resp.statusCode != 200) {
        throw Exception('Backend respondió ${resp.statusCode}: ${resp.body}');
      }

      final dir = await getTemporaryDirectory();
      final archivo = File('${dir.path}/planilla_guardia_${_anio}_${_mes.toString().padLeft(2, '0')}.pdf');
      await archivo.writeAsBytes(resp.bodyBytes);

      await Share.shareXFiles(
        [XFile(archivo.path)],
        text: 'Planilla de guardia $mesNombre $_anio',
      );
      if (!mounted) return;
      setState(() {
        _generando = false;
        _mensaje = 'PDF generado y compartido.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generando = false;
        _mensaje = 'Error al generar: $e\n¿Está levantado el backend y configurado apiReportesUrl?';
      });
    }
  }

  String get mesNombre => _meses[_mes - 1];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reporte')),
      body: _cargandoCat
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() {
                          _mes--;
                          if (_mes == 0) {
                            _mes = 12;
                            _anio--;
                          }
                        }),
                      ),
                      Text('$mesNombre $_anio', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() {
                          _mes++;
                          if (_mes == 13) {
                            _mes = 1;
                            _anio++;
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _unidadId,
                    decoration: const InputDecoration(labelText: 'Unidad', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('(todas)')),
                      ..._unidades.map((u) => DropdownMenuItem(value: u.id, child: Text(u.nombre))),
                    ],
                    onChanged: (v) => setState(() {
                      _unidadId = v;
                      _sectorId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _sectorId,
                    decoration: const InputDecoration(labelText: 'Sector', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('(todos)')),
                      ..._sectoresUnidad.map(
                        (s) => DropdownMenuItem(value: s.id, child: Text(s.nombre)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _sectorId = v),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _generando ? null : _generar,
                    icon: _generando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Generar PDF'),
                    ),
                  ),
                  if (_mensaje != null) ...[
                    const SizedBox(height: 16),
                    Text(_mensaje!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'El PDF se genera en el backend (FastAPI + WeasyPrint) '
                    'con el mismo diseño impreso: landscape, logos y firmas. '
                    'La clave de Supabase nunca viaja a la app.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}