import 'dart:io';

import 'package:agrolweza_app/crops.dart';
import 'package:agrolweza_app/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acrescentar uma cultura toca em quatro sítios: crops.dart, pubspec.yaml, os
/// ficheiros em assets/models/ e o diagnosisCatalog. Esquecer um deles não dá
/// erro de compilação:
///  - sem o pubspec, o asset falta em RUNTIME, já no telemóvel do agricultor;
///  - sem a entrada no catálogo, o `info` cai em silêncio para 'unknown' e o
///    app mostra "não foi possível confirmar" num diagnóstico que correu bem.
/// Estes testes fecham esses quatro sítios contra o descuido.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  group('registo de culturas', () {
    test('a chave do mapa é sempre o id da própria cultura', () {
      cropCatalog.forEach((key, crop) => expect(crop.id, key));
    });

    test('nenhuma cultura fica sem nome para mostrar', () {
      for (final crop in cropCatalog.values) {
        expect(crop.label.trim(), isNotEmpty, reason: crop.id);
      }
    });

    test('o limiar de recusa está entre 0 e 1', () {
      for (final crop in cropCatalog.values) {
        expect(crop.abstentionThreshold, greaterThan(0), reason: crop.id);
        expect(crop.abstentionThreshold, lessThanOrEqualTo(1), reason: crop.id);
      }
    });

    test('duas culturas nunca partilham o mesmo modelo', () {
      final modelos = cropCatalog.values.map((c) => c.modelAsset).toList();
      expect(modelos.toSet().length, modelos.length);
    });
  });

  group('cada cultura está declarada e presente', () {
    for (final crop in cropCatalog.values) {
      test('${crop.id}: modelo e etiquetas existem em disco', () {
        expect(File(crop.modelAsset).existsSync(), isTrue,
            reason: 'falta ${crop.modelAsset}');
        expect(File(crop.labelsAsset).existsSync(), isTrue,
            reason: 'falta ${crop.labelsAsset}');
      });

      test('${crop.id}: modelo e etiquetas registados no pubspec.yaml', () {
        expect(pubspec, contains(crop.modelAsset),
            reason: '${crop.modelAsset} não está na secção assets do pubspec; '
                'faltaria em runtime, no telemóvel');
        expect(pubspec, contains(crop.labelsAsset),
            reason: '${crop.labelsAsset} não está na secção assets do pubspec');
      });

      test('${crop.id}: toda a etiqueta tem entrada no diagnosisCatalog', () {
        final etiquetas = File(crop.labelsAsset)
            .readAsStringSync()
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty);

        expect(etiquetas, isNotEmpty, reason: '${crop.labelsAsset} está vazio');

        for (final etiqueta in etiquetas) {
          expect(
            diagnosisCatalog.containsKey(etiqueta),
            isTrue,
            reason: 'a classe "$etiqueta" do modelo de ${crop.id} não tem '
                'entrada no diagnosisCatalog: o app mostraria "não foi '
                'possível confirmar" num diagnóstico que correu bem',
          );
        }
      });
    }
  });

  group('cropLabelFor', () {
    test('devolve o nome da cultura conhecida', () {
      expect(cropLabelFor('feijao'), 'Feijão');
      expect(cropLabelFor('mandioca'), 'Mandioca');
    });

    test('registo antigo sem cultura não rebenta nem mostra vazio', () {
      expect(cropLabelFor(''), 'Não indicada');
    });

    test('cultura descontinuada devolve o próprio id em vez de rebentar', () {
      expect(cropLabelFor('batata_rena'), 'batata_rena');
    });
  });
}
