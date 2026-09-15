/// Culturas suportadas pelo app.
///
/// Cada cultura traz o SEU modelo, as SUAS etiquetas e o SEU limiar de recusa.
/// Nada disto pode voltar a ser constante partilhada: os modelos diferem na
/// resolução de entrada (mandioca 224, feijão 320) e o limiar certo depende da
/// calibração de cada um.
///
/// Ficheiro sem dependências de Flutter de propósito, para poder ser testado
/// sem plataforma. O ícone de cada cultura é escolhido na UI, não aqui.
class Crop {
  /// Identificador persistido no histórico. Não mudar: há registos gravados.
  final String id;

  /// Nome mostrado ao agricultor.
  final String label;

  final String modelAsset;
  final String labelsAsset;

  /// Abaixo deste valor o app recusa o diagnóstico específico e pede nova
  /// fotografia, em vez de arriscar uma classe errada.
  ///
  /// ATENÇÃO: o limiar filtra INCERTEZA, não IGNORÂNCIA. Medição de 2026-09-15
  /// com o modelo do feijão: 78% de imagens de culturas que o modelo nunca viu
  /// passaram um limiar de 0.9. Subir este número não protege contra o que o
  /// modelo desconhece — só rejeita fotografias boas. Ver AGL-15.
  final double abstentionThreshold;

  const Crop({
    required this.id,
    required this.label,
    required this.modelAsset,
    required this.labelsAsset,
    required this.abstentionThreshold,
  });
}

/// Registo das culturas. A ordem é a que aparece no seletor.
///
/// Ao acrescentar uma cultura: registar os dois ficheiros no `pubspec.yaml`,
/// e acrescentar as classes do modelo ao `diagnosisCatalog` em fixtures.dart
/// com os mesmos ids do ficheiro de etiquetas.
const Map<String, Crop> cropCatalog = {
  'feijao': Crop(
    id: 'feijao',
    label: 'Feijão',
    modelAsset: 'assets/models/agrolweza_beans_v2.tflite',
    labelsAsset: 'assets/models/agrolweza_beans_labels.txt',
    abstentionThreshold: 0.6,
  ),
  'mandioca': Crop(
    id: 'mandioca',
    label: 'Mandioca',
    modelAsset: 'assets/models/agrolweza_cassava_baseline.tflite',
    labelsAsset: 'assets/models/agrolweza_class_labels.txt',
    abstentionThreshold: 0.6,
  ),
};

/// Nome a mostrar para um id de cultura vindo do histórico.
///
/// Registos antigos podem ter um id que já não existe no catálogo, ou vazio.
/// Nesse caso devolve-se o próprio id em vez de rebentar — o histórico é para
/// ser lido, não para falhar por causa de uma cultura descontinuada.
String cropLabelFor(String cropId) =>
    cropCatalog[cropId]?.label ?? (cropId.isEmpty ? 'Não indicada' : cropId);
