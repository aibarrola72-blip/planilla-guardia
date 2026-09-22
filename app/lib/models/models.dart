/// Modelos de datos usados por la app (espejos de las tablas de Supabase).
library;

class Unidad {
  final int id;
  final String nombre;
  final bool activo;

  Unidad({required this.id, required this.nombre, required this.activo});

  factory Unidad.fromJson(Map<String, dynamic> json) => Unidad(
        id: json['id'] as int,
        nombre: json['nombre'] as String? ?? '',
        activo: json['activo'] as bool? ?? true,
      );
}

class Sector {
  final int id;
  final int? unidadId;
  final String nombre;
  final bool activo;

  Sector({required this.id, this.unidadId, required this.nombre, required this.activo});

  factory Sector.fromJson(Map<String, dynamic> json) => Sector(
        id: json['id'] as int,
        unidadId: json['unidad_id'] as int?,
        nombre: json['nombre'] as String? ?? '',
        activo: json['activo'] as bool? ?? true,
      );
}

class Cargo {
  final int id;
  final String nombre;
  final bool activo;

  Cargo({required this.id, required this.nombre, required this.activo});

  factory Cargo.fromJson(Map<String, dynamic> json) => Cargo(
        id: json['id'] as int,
        nombre: json['nombre'] as String? ?? '',
        activo: json['activo'] as bool? ?? true,
      );
}

class Turno {
  final int id;
  final String codigo;
  final String descripcion;
  final String horaInicio;
  final String horaFin;
  final bool activo;

  Turno({
    required this.id,
    required this.codigo,
    required this.descripcion,
    required this.horaInicio,
    required this.horaFin,
    required this.activo,
  });

  factory Turno.fromJson(Map<String, dynamic> json) => Turno(
        id: json['id'] as int,
        codigo: json['codigo'] as String? ?? '',
        descripcion: json['descripcion'] as String? ?? '',
        horaInicio: json['hora_inicio'] as String? ?? '',
        horaFin: json['hora_fin'] as String? ?? '',
        activo: json['activo'] as bool? ?? true,
      );

  String get horario => '$horaInicio - $horaFin';
}

class Persona {
  final int id;
  final String nombre;
  final String ci;
  final String registro;
  final int? unidadId;
  final int? sectorId;
  final int? cargoId;
  final int? turnoId;
  final String estado;
  final int orden;
  final String? cargoNombre;
  final String? sectorNombre;
  final String? turnoCodigo;
  final DateTime? nocheDesde;
  final String? nocheInicioLinea;

  const Persona({
    required this.id,
    required this.nombre,
    required this.ci,
    required this.registro,
    this.unidadId,
    this.sectorId,
    this.cargoId,
    this.turnoId,
    required this.estado,
    required this.orden,
    this.cargoNombre,
    this.sectorNombre,
    this.turnoCodigo,
    this.nocheDesde,
    this.nocheInicioLinea,
  });

  bool get estaActivo => estado == 'ACTIVO';

  factory Persona.fromJson(Map<String, dynamic> json) {
    final cargo = json['cargo'];
    final sector = json['sector'];
    final turno = json['turno'];
    final nocheDesde = json['noche_desde'] as String?;
    return Persona(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? '',
      ci: json['ci'] as String? ?? '',
      registro: json['registro'] as String? ?? '',
      unidadId: json['unidad_id'] as int?,
      sectorId: json['sector_id'] as int?,
      cargoId: json['cargo_id'] as int?,
      turnoId: json['turno_id'] as int?,
      estado: json['estado'] as String? ?? 'ACTIVO',
      orden: json['orden'] as int? ?? 0,
      cargoNombre: (cargo is Map) ? (cargo['nombre'] as String?) : null,
      sectorNombre: (sector is Map) ? (sector['nombre'] as String?) : null,
      turnoCodigo: (turno is Map) ? (turno['codigo'] as String?) : null,
      nocheDesde: nocheDesde == null ? null : DateTime.parse(nocheDesde),
      nocheInicioLinea: json['noche_inicio_linea'] as String?,
    );
  }

  /// Nombre para la planilla/menú: "Nombre + Cargo + Sector".
  String get etiqueta => [nombre, cargoNombre ?? '', sectorNombre ?? '']
      .where((s) => s.isNotEmpty)
      .join(' ');

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'ci': ci,
        'registro': registro,
        'unidad_id': unidadId,
        'sector_id': sectorId,
        'cargo_id': cargoId,
        'turno_id': turnoId,
        'estado': estado,
        'orden': orden,
        'noche_desde': nocheDesde?.toIso8601String().split('T').first,
        'noche_inicio_linea': nocheInicioLinea,
      };
}

/// Periodo de ausencia (vacación o libre) por persona.
class AusenciaRango {
  final int id;
  final int personaId;
  final DateTime inicio;
  final DateTime fin;
  final String? observacion;

  const AusenciaRango({
    required this.id,
    required this.personaId,
    required this.inicio,
    required this.fin,
    this.observacion,
  });

  factory AusenciaRango.fromJson(Map<String, dynamic> json) => AusenciaRango(
        id: json['id'] as int,
        personaId: json['persona_id'] as int,
        inicio: DateTime.parse(json['fecha_inicio'] as String),
        fin: DateTime.parse(json['fecha_fin'] as String),
        observacion: json['observacion'] as String?,
      );
}