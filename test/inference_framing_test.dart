import 'dart:ui';

import 'package:agrolweza_app/inference_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A moldura-guia so serve para alguma coisa se o recorte dela chegar ao
/// modelo com os mesmos pixels que o agricultor viu no ecra. Estes testes
/// guardam essa correspondencia.
void main() {
  group('frameToImageRect', () {
    test('viewport e imagem com o mesmo aspeto: recorte proporcional', () {
      // Ecra 400x800, foto 800x1600 (mesmo aspeto, escala 2x na exibicao).
      final rect = frameToImageRect(
        framing: CaptureFraming(
          frame: const Rect.fromLTWH(40, 140, 320, 320),
          viewport: const Size(400, 800),
        ),
        imageWidth: 800,
        imageHeight: 1600,
      )!;

      // scale = 0.5, sem sobra: cada coordenada do ecra vale 2 px de imagem.
      expect(rect.left, closeTo(80, 0.01));
      expect(rect.top, closeTo(280, 0.01));
      expect(rect.width, closeTo(640, 0.01));
      expect(rect.height, closeTo(640, 0.01));
    });

    test('imagem mais larga que o ecra: desconta a sobra cortada aos lados',
        () {
      // Ecra 400x800 (aspeto 0.5), foto 1200x1600 (aspeto 0.75). Em cover a
      // altura manda: scale = 800/1600 = 0.5, largura exibida = 600, logo
      // sobram 100 de cada lado para fora do ecra.
      final rect = frameToImageRect(
        framing: CaptureFraming(
          frame: const Rect.fromLTWH(0, 0, 400, 400),
          viewport: const Size(400, 800),
        ),
        imageWidth: 1200,
        imageHeight: 1600,
      )!;

      // x=0 no ecra corresponde a 100/0.5 = 200 px na imagem.
      expect(rect.left, closeTo(200, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.width, closeTo(800, 0.01));
      expect(rect.height, closeTo(800, 0.01));
    });

    test('recorte nunca sai fora dos limites da imagem', () {
      final rect = frameToImageRect(
        framing: CaptureFraming(
          // Moldura propositadamente a transbordar o viewport.
          frame: const Rect.fromLTWH(-50, 700, 500, 500),
          viewport: const Size(400, 800),
        ),
        imageWidth: 800,
        imageHeight: 1600,
      )!;

      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(800));
      expect(rect.bottom, lessThanOrEqualTo(1600));
    });

    test('imagem minuscula devolve null para o chamador usar a foto inteira',
        () {
      final rect = frameToImageRect(
        framing: CaptureFraming(
          frame: const Rect.fromLTWH(40, 140, 320, 320),
          viewport: const Size(400, 800),
        ),
        imageWidth: 40,
        imageHeight: 80,
      );

      expect(rect, isNull);
    });

    test('viewport por medir devolve null em vez de rebentar', () {
      final rect = frameToImageRect(
        framing: CaptureFraming(
          frame: Rect.zero,
          viewport: Size.zero,
        ),
        imageWidth: 800,
        imageHeight: 1600,
      );

      expect(rect, isNull);
    });
  });
}
