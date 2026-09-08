import 'dart:math';

import 'fixtures.dart';

/// Estados de sincronizacao previstos na especificacao do prototipo.
///
/// Os valores persistidos sao propositadamente curtos e estaveis: alterar
/// estas strings invalida o historico ja gravado nos telemoveis em campo.
abstract final class SyncStatus {
  /// Aguarda envio (`pending-sync` na especificacao).
  static const pending = 'pending';

  /// Aceite pelo destino.
  static const synced = 'synced';

  /// Falha recuperavel (`sync-error` na especificacao). Continua na fila.
  static const error = 'error';
}

class HistoryItem {
  /// Identificador unico e estavel do diagnostico.
  ///
  /// E a chave de idempotencia da sincronizacao: o backend da fase 2 usa-a
  /// para reconhecer um reenvio apos falha em vez de criar um duplicado.
  final String id;
  final String diagnosisId;
  final double confidence;
  final String crop;
  /// Local onde o diagnostico foi feito. Vazio nos registos gravados antes de
  /// o campo existir (migracao) ou se ainda nao foi escolhido.
  final String province;
  final String municipality;
  final DateTime createdAt;
  final String syncStatus;

  HistoryItem({
    required this.id,
    required this.diagnosisId,
    required this.confidence,
    required this.crop,
    this.province = '',
    this.municipality = '',
    required this.createdAt,
    required this.syncStatus,
  });

  static final _random = Random();

  /// Gera um id unico no proprio dispositivo, sem depender de rede nem de
  /// pacote externo. Timestamp em microssegundos evita colisao entre sessoes;
  /// o sufixo aleatorio cobre gravacoes no mesmo microssegundo.
  static String newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0x7FFFFFFF).toRadixString(36);
    return 'dx-$stamp-$suffix';
  }

  bool get isSynced => syncStatus == SyncStatus.synced;

  DiagnosisInfo get info =>
      diagnosisCatalog[diagnosisId] ?? diagnosisCatalog['unknown']!;

  HistoryItem copyWith({String? syncStatus}) => HistoryItem(
        id: id,
        diagnosisId: diagnosisId,
        confidence: confidence,
        crop: crop,
        province: province,
        municipality: municipality,
        createdAt: createdAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'diagnosisId': diagnosisId,
        'confidence': confidence,
        'crop': crop,
        'province': province,
        'municipality': municipality,
        'createdAt': createdAt.toIso8601String(),
        'syncStatus': syncStatus,
      };

  static HistoryItem fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    final diagnosisId = diagnosisCatalog.containsKey(json['diagnosisId'])
        ? json['diagnosisId'] as String
        : 'unknown';
    return HistoryItem(
      // Registos gravados antes de existir o id continuam validos: derivam um
      // id estavel dos proprios dados em vez de serem descartados no load.
      id: json['id'] as String? ??
          'legacy-${createdAt.microsecondsSinceEpoch}-$diagnosisId',
      diagnosisId: diagnosisId,
      confidence: (json['confidence'] as num).toDouble(),
      crop: json['crop'] as String,
      // Registos antigos nao tinham localizacao: assume vazio, nao descarta.
      province: json['province'] as String? ?? '',
      municipality: json['municipality'] as String? ?? '',
      createdAt: createdAt,
      syncStatus: json['syncStatus'] as String,
    );
  }
}
