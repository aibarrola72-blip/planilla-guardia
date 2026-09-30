import 'package:flutter_test/flutter_test.dart';

import 'package:ineram_app/models/models.dart';

void main() {
  group('Turno', () {
    test('lee regla/offset/orden desde la BD', () {
      final t = Turno.fromJson({
        'id': 5,
        'codigo': 'N3',
        'descripcion': 'Noche 3',
        'hora_inicio': '18:00',
        'hora_fin': '06:00',
        'activo': true,
        'regla': 'NOCTURNA',
        'rotacion_offset': 2,
        'orden_grupo': 2,
      });
      expect(t.regla, 'NOCTURNA');
      expect(t.rotacionOffset, 2);
      expect(t.offsetNocturna, 2);
      expect(t.ordenGrupo, 2);
    });

    test('fallback legado cuando la BD no tiene las columnas', () {
      final t = Turno.fromJson({
        'id': 9,
        'codigo': 'M1',
        'descripcion': 'Mañana',
        'hora_inicio': '06:30',
        'hora_fin': '12:30',
        'activo': true,
      });
      expect(t.regla, 'LABORABLE');
      expect(t.rotacionOffset, isNull);
      expect(t.ordenGrupo, 99);

      final n2 = Turno.fromJson({'id': 4, 'codigo': 'N2', 'activo': true});
      expect(n2.regla, 'NOCTURNA');
      expect(n2.offsetNocturna, 1);
    });

    test('código desconocido queda OTRO (solo asignación manual)', () {
      expect(Turno.fromJson({'id': 99, 'codigo': 'X1'}).regla, 'OTRO');
    });
  });

  group('Persona', () {
    test('turnoGrupo usa orden_grupo y cae al orden histórico', () {
      final conDato = Persona.fromJson({
        'id': 1,
        'nombre': 'Lic. Test',
        'estado': 'ACTIVO',
        'orden': 1,
        'turno': {'codigo': 'M1', 'orden_grupo': 0},
      });
      expect(conDato.turnoGrupo, 0);

      final sinDato = Persona.fromJson({
        'id': 2,
        'nombre': 'Lic. Test 2',
        'estado': 'ACTIVO',
        'orden': 1,
        'turno': {'codigo': 'N3'},
      });
      expect(sinDato.turnoGrupo, 4);
    });
  });
}
