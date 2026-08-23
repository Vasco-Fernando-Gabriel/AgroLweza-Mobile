import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

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

  Future<InferenceResult> classify(File imageFile) async {
    await _ensureLoaded();

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Não foi possível ler a imagem selecionada.');
    }
    final resized = img.copyResize(
      decoded,
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

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
