import 'package:agrolweza_app/inference_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// O indice da classe vencedora do modelo e usado para indexar a lista de
/// etiquetas. Se o .tflite e o .txt forem de culturas diferentes, o app pode
/// mostrar em silencio o nome de outra doenca e mandar tratar a praga errada.
/// Estes testes guardam esse emparelhamento.
void main() {
  group('assertModelMatchesLabels', () {
    const beans = ['mancha_angular', 'ferrugem', 'saudavel'];
    const cassava = [
      'healthy',
      'cassava_mosaic',
      'cassava_bacterial_blight',
      'cassava_brown_streak',
      'cassava_green_mottle',
    ];

    void check(List<int> shape, List<String> labels) =>
        assertModelMatchesLabels(
          outputShape: shape,
          labels: labels,
          modelAsset: 'modelo.tflite',
          labelsAsset: 'etiquetas.txt',
        );

    test('par coerente passa: feijao 3 classes com 3 etiquetas', () {
      expect(() => check([1, 3], beans), returnsNormally);
    });

    test('par coerente passa: mandioca 5 classes com 5 etiquetas', () {
      expect(() => check([1, 5], cassava), returnsNormally);
    });

    test('culturas trocadas falham: modelo de feijao com etiquetas de mandioca',
        () {
      expect(
        () => check([1, 3], cassava),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mensagem',
            allOf(contains('3'), contains('5'), contains('culturas')),
          ),
        ),
      );
    });

    test('culturas trocadas falham: modelo de mandioca com etiquetas de feijao',
        () {
      expect(() => check([1, 5], beans), throwsStateError);
    });

    test('ficheiro de etiquetas vazio falha com mensagem propria', () {
      expect(
        () => check([1, 3], const []),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mensagem',
            contains('vazio'),
          ),
        ),
      );
    });

    test('saida sem a dimensao de batch e recusada', () {
      expect(() => check([3], beans), throwsStateError);
    });

    test('saida com dimensoes a mais e recusada', () {
      expect(() => check([1, 3, 3], beans), throwsStateError);
    });

    test('batch diferente de 1 e recusado', () {
      expect(() => check([2, 3], beans), throwsStateError);
    });

    test('zero classes e recusado antes de comparar com as etiquetas', () {
      expect(() => check([1, 0], beans), throwsStateError);
    });
  });
}
