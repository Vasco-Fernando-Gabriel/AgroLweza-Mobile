import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'crops.dart';

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

/// Confere que o modelo carregado e o ficheiro de etiquetas são o mesmo par.
///
/// O buffer de saída da inferência é dimensionado pelo número de etiquetas, e
/// o índice da classe vencedora é usado para indexar essa lista. Se o `.tflite`
/// de uma cultura for emparelhado com o `.txt` de outra, na melhor das
/// hipóteses rebenta; na pior, alinha mal e devolve em silêncio o nome de
/// outra doença — o agricultor trata a praga errada e nunca ninguém percebe.
/// Por isso falha-se aqui, cedo e com contexto, em vez de deixar o erro seguir.
///
/// [outputShape] vem do tensor de saída do modelo e deve ser `[1, N]`.
void assertModelMatchesLabels({
  required List<int> outputShape,
  required List<String> labels,
  required String modelAsset,
  required String labelsAsset,
}) {
  if (outputShape.length != 2 || outputShape[0] != 1 || outputShape[1] <= 0) {
    throw StateError(
      'Modelo $modelAsset com saída inesperada $outputShape. '
      'Esperado [1, N] com N classes.',
    );
  }
  if (labels.isEmpty) {
    throw StateError('Ficheiro de etiquetas $labelsAsset está vazio.');
  }
  final classes = outputShape[1];
  if (labels.length != classes) {
    throw StateError(
      'Modelo e etiquetas não correspondem: $modelAsset devolve $classes '
      'classes, mas $labelsAsset tem ${labels.length} '
      '(${labels.join(', ')}). O .tflite e o .txt parecem ser de culturas '
      'diferentes.',
    );
  }
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

/// Roda um modelo Agrolweza (treinado no Colab) localmente no dispositivo via
/// TFLite. Sem chamadas de rede.
///
/// Não assume a resolução de entrada: lê-a do `.tflite` carregado, porque cada
/// cultura tem o seu modelo. Os pixels entram crus em `[0, 255]` — ver a nota
/// em [classify] antes de mexer nisso.
class InferenceService {
  Interpreter? _interpreter;
  List<String> _labels = const [];
  int? _inputSize;

  /// Cultura cujo modelo está neste momento carregado, ou null se ainda nenhum.
  Crop? _loadedCrop;

  /// Lado do quadrado que o modelo espera à entrada, lido do próprio `.tflite`.
  /// Não é constante: cada cultura tem o seu modelo e as resoluções diferem
  /// (mandioca 224, feijão 320). Só está disponível depois de [_ensureLoaded].
  int get inputSize {
    final size = _inputSize;
    if (size == null) {
      throw StateError(
        'inputSize só existe depois de o modelo estar carregado.',
      );
    }
    return size;
  }

  /// Garante que o modelo da [crop] pedida está carregado.
  ///
  /// Mantém-se UM modelo de cada vez: ao trocar de cultura larga-se o anterior
  /// em vez de deixar os dois residentes. Custa uns milissegundos na troca, que
  /// é rara (escolhe-se a cultura uma vez), e poupa memória nativa nos
  /// telemóveis baratos que são o alvo do app.
  Future<void> _ensureLoaded(Crop crop) async {
    if (_loadedCrop != null && _loadedCrop!.id != crop.id) {
      _releaseModel();
    }
    if (_interpreter == null) {
      final interpreter = await Interpreter.fromAsset(crop.modelAsset);
      try {
        _inputSize = _readInputSize(interpreter);
      } catch (_) {
        // Modelo incompatível: fecha o interpreter antes de propagar, senão
        // fica memória nativa presa sem ninguém para lhe chamar close().
        interpreter.close();
        rethrow;
      }
      _interpreter = interpreter;
    }
    if (_labels.isEmpty) {
      final raw = await rootBundle.loadString(crop.labelsAsset);
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    assertModelMatchesLabels(
      outputShape: _interpreter!.getOutputTensor(0).shape,
      labels: _labels,
      modelAsset: crop.modelAsset,
      labelsAsset: crop.labelsAsset,
    );
    _loadedCrop = crop;
  }

  /// Larga o modelo carregado e todo o estado que dele deriva.
  void _releaseModel() {
    _interpreter?.close();
    _interpreter = null;
    _inputSize = null;
    _labels = const [];
    _loadedCrop = null;
  }

  /// Lê a resolução de entrada do modelo a partir do tensor de entrada.
  /// O shape é `[1, altura, largura, canais]`; exigimos imagem quadrada RGB
  /// porque é isso que o pipeline de recorte e redimensionamento produz.
  int _readInputSize(Interpreter interpreter) {
    final shape = interpreter.getInputTensor(0).shape;
    if (shape.length != 4 ||
        shape[1] != shape[2] ||
        shape[3] != 3 ||
        shape[1] <= 0) {
      throw StateError(
        'Modelo com entrada inesperada $shape. '
        'Esperado [1, N, N, 3] (imagem quadrada RGB).',
      );
    }
    return shape[1];
  }

  /// Classifica [imageFile] com o modelo da [crop] indicada. Quando a
  /// fotografia veio da câmara com moldura-guia, [framing] traz a geometria
  /// dessa moldura e só o que estava lá dentro é entregue ao modelo.
  Future<InferenceResult> classify(
    File imageFile, {
    required Crop crop,
    CaptureFraming? framing,
  }) async {
    await _ensureLoaded(crop);

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

  void dispose() => _releaseModel();
}
