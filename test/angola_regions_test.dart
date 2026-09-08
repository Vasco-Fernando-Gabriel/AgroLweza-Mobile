import 'package:agrolweza_app/angola_regions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sao 21 provincias (divisao de 2024)', () {
    expect(angolaProvinces.length, 21);
  });

  test('as novas provincias de 2024 estao presentes', () {
    for (final p in ['Cuando', 'Cubango', 'Icolo e Bengo', 'Moxico Leste']) {
      expect(angolaProvinces, contains(p), reason: 'falta $p');
    }
  });

  test('toda provincia listada tem municipios', () {
    for (final p in angolaProvinces) {
      expect(municipalitiesOf(p), isNotEmpty, reason: '$p sem municipios');
    }
  });

  test('nao ha provincias no mapa fora da lista oficial', () {
    for (final p in angolaMunicipalities.keys) {
      expect(angolaProvinces, contains(p), reason: '$p nao esta na lista');
    }
  });

  test('municipios sem duplicados dentro da provincia', () {
    for (final p in angolaProvinces) {
      final m = municipalitiesOf(p);
      expect(m.toSet().length, m.length, reason: '$p tem municipio duplicado');
    }
  });

  test('provincia desconhecida devolve lista vazia', () {
    expect(municipalitiesOf('Inexistente'), isEmpty);
  });
}
