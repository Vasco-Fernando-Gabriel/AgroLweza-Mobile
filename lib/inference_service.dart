import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Geometria da moldura-guia no momento em que a fotografia foi tirada.
///
/// A moldura desenhada no ecra so tem valor se o recorte dela chegar ao
/// modelo: caso contrario o agricultor enquadra uma folha e o modelo continua
/// a receber a moita inteira. [frame] e [viewport] vem em coordenadas logicas
/// do ecra; a conversao para pixeis da imagem acontece em [InferenceService].
class CaptureFraming {
  /// Retangulo da moldura, nas coordenadas do [viewport].
  final Rect frame;

  /// Area onde o preview da camara foi desenhado, com BoxFit.cover.
  final Size viewport;

  const CaptureFraming({required this.frame, required this.viewport});
}

/// Lado minimo, em pixeis, de um recorte que ainda vale a pena analisar.
const int kMinCropSide = 64;

/// Converte a moldura desenhada no ecra para um retangulo em pixeis da imagem.
///
/// O preview e pintado com BoxFit.cover: a imagem e escalada pelo MAIOR dos
/// dois fatores e o excedente sai centrado para fora do ecra. Aqui desfaz-se
/// essa transformacao. Devolve null quando o resultado nao serve (viewport ou
/// imagem degenerada, recorte pequeno de mais) — nesse caso o chamador deve
/// usar a imagem inteira em vez de falhar a analise.
Rect? frameToImageRect({
  required CaptureFraming framing,
  required int imageWidth,
  required int imageHeight,
}) {
  final viewport = framing.viewport;
  if (viewport.width <= 0 || viewport.height <= 0) return null;
  if (imageWidth <= 0 || imageHeight <= 0) return null;

  final scale = math.max(
    viewport.width / imageWidth,
    viewport.height / imageHeight,
  );
  if (scale <= 0) return null;

  // Sobra da imagem escalada que fica fora do ecra, de cada lado.
  final offsetX = (imageWidth * scale - viewport.width) / 2;
  final offsetY = (imageHeight * scale - viewport.height) / 2;

  final left = ((framing.frame.left + offsetX) / scale)
      .clamp(0.0, imageWidth.toDouble());
  final top = ((framing.frame.top + offsetY) / scale)
      .clamp(0.0, imageHeight.toDouble());
  final width = math.min(framing.frame.width / scale, imageWidth - left);
  final height = math.min(framing.frame.height / scale, imageHeight - top);

  if (width < kMinCropSide || height < kMinCropSide) return null;

  return Rect.fromLTWH(left, top, width, height);
}

/// Resultado bruto de uma inferência: classe mais provável, a sua confiança
/// (softmax) e o vetor completo de probabilidades por classe.
class InferenceResult {
  final String classId;
  final double confidence;
  final Map<String, double> probabilities;

  const InferenceResult({
    required this.classId,
    required this.confidence,
    required this.probabilities,
  });
}

/// Roda o modelo Agrolweza (MobileNetV3Small, treinado no Colab) localmente
/// no dispositivo via TFLite. Sem chamadas de rede.
class InferenceService {
  static const _modelAsset = 'assets/models/agrolweza_cassava_baseline.tflite';
  static const _labelsAsset = 'assets/models/agrolweza_class_labels.txt';
  static const inputSize = 224;

  /// Abaixo deste valor, o app deve recusar o diagnóstico específico e pedir
  /// nova fotografia em vez de arriscar uma classe errada.
  static const abstentionThreshold = 0.6;

  Interpreter? _interpreter;
  List<String> _labels = const [];

  Future<void> _ensureLoaded() async {
    _interpreter ??= await Interpreter.fromAsset(_modelAsset);
    if (_labels.isEmpty) {
      final raw = await rootBundle.loadString(_labelsAsset);
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  }

  /// Classifica [imageFile]. Quando a fotografia veio da câmara com
  /// moldura-guia, [framing] traz a geometria dessa moldura e só o que estava
  /// lá dentro é entregue ao modelo.
  Future<InferenceResult> classify(
    File imageFile, {
    CaptureFraming? framing,
  }) async {
    await _ensureLoaded();

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Não foi possível ler a imagem selecionada.');
    }
    // A foto chega com a orientação em EXIF; sem assar essa rotação nos pixels
    // o recorte cairia no sítio errado numa foto tirada de lado.
    final oriented = img.bakeOrientation(decoded);
    final cropped =
        framing == null ? oriented : _cropToFrame(oriented, framing);

    final resized = img.copyResize(
      cropped,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // O modelo foi treinado com tf.keras.applications.mobilenet_v3.preprocess_input,
    // que é uma identidade: o próprio MobileNetV3Small do Keras já embute uma
    // camada de Rescaling ([0,255] -> [-1,1]) internamente. Por isso aqui
    // entram valores de pixel crus (0-255), sem normalização manual.
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            pixel.r.toDouble(),
            pixel.g.toDouble(),
            pixel.b.toDouble(),
          ];
        }),
      ),
    );

    final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));
    _interpreter!.run(input, output);

    final probs = output[0];
    var bestIndex = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIndex]) bestIndex = i;
    }

    final probabilities = <String, double>{
      for (var i = 0; i < _labels.length; i++) _labels[i]: probs[i].toDouble(),
    };

    return InferenceResult(
      classId: _labels[bestIndex],
      confidence: probs[bestIndex].toDouble(),
      probabilities: probabilities,
    );
  }

  img.Image _cropToFrame(img.Image source, CaptureFraming framing) {
    final rect = frameToImageRect(
      framing: framing,
      imageWidth: source.width,
      imageHeight: source.height,
    );
    if (rect == null) return source;

    return img.copyCrop(
      source,
      x: rect.left.round(),
      y: rect.top.round(),
      width: rect.width.round(),
      height: rect.height.round(),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
