import 'package:flutter_test/flutter_test.dart';

import 'package:ineram_app/config.dart';

void main() {
  test('Configuración de instituciones cargada', () {
    expect(AppConfig.institucion, contains('INSTITUTO NACIONAL'));
    expect(AppConfig.institucionSub, contains('INERAM'));
  });
}