import 'dart:convert';
import 'dart:io';

import 'history_item.dart';

/// Desfecho do envio de um diagnostico.
enum SyncOutcome { success, failure }

/// Transporte de sincronizacao.
///
/// A fase 2 (backend) troca apenas a implementacao: a fila, a persistencia e a
/// UI ficam intactas. O contrato exige idempotencia por [HistoryItem.id], para
/// cumprir o criterio de aceite "uma falha de sincronizacao pode ser repetida
/// sem duplicar o diagnostico".
abstract interface class SyncTransport {
  Future<SyncOutcome> send(HistoryItem item);
}

/// Fase 1: ainda nao existe backend.
///
/// A fila e real (percorre os pendentes, marca cada item individualmente e
/// sabe registar falha), apenas o transporte e simulado, como previsto no
/// escopo do prototipo. Substituir por um transporte HTTP nao exige mudancas
/// fora deste ficheiro.
class SimulatedSyncTransport implements SyncTransport {
  const SimulatedSyncTransport();

  @override
  Future<SyncOutcome> send(HistoryItem item) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return SyncOutcome.success;
  }
}

/// Fase 2: transporte HTTP real.
///
/// Faz um POST JSON por diagnostico para [endpoint]. Envia apenas os metadados
/// que o [HistoryItem] ja carrega (id, diagnosisId, confidence, crop, province,
/// municipality, createdAt); a fotografia e o consentimento entram numa fase
/// posterior, com o proprio gate legal.
///
/// Idempotencia por [HistoryItem.id]: o mesmo id vai no corpo e no cabecalho
/// `Idempotency-Key`, e um `409 Conflict` (o destino ja tinha esse id) conta
/// como sucesso. Assim, repetir a sincronizacao depois de uma falha nunca
/// duplica o diagnostico, cumprindo o criterio de aceite.
///
/// Usa `dart:io HttpClient` de proposito (mesma stack ja usada no app para o
/// probe de conectividade), para nao acrescentar dependencia de pacote.
class HttpSyncTransport implements SyncTransport {
  /// URL completa do recurso de diagnosticos, ex:
  /// `http://10.0.2.2:8080/v1/diagnosticos` (10.0.2.2 = host da maquina visto
  /// de dentro do emulador Android).
  final Uri endpoint;
  final Duration timeout;

  HttpSyncTransport({
    required this.endpoint,
    this.timeout = const Duration(seconds: 10),
  });

  @override
  Future<SyncOutcome> send(HistoryItem item) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(endpoint).timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.headers.set('Idempotency-Key', item.id);
      req.add(utf8.encode(jsonEncode(_payload(item))));
      final res = await req.close().timeout(timeout);
      // Esgota o corpo para libertar a ligacao mesmo quando nao o lemos.
      await res.drain<void>();
      final ok = (res.statusCode >= 200 && res.statusCode < 300) ||
          res.statusCode == HttpStatus.conflict;
      return ok ? SyncOutcome.success : SyncOutcome.failure;
    } catch (_) {
      // Timeout, rede caida, DNS/TLS: falha recuperavel. O item fica na fila
      // com estado de erro e sera reenviado na proxima sincronizacao.
      return SyncOutcome.failure;
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _payload(HistoryItem item) => {
        'id': item.id,
        'diagnosisId': item.diagnosisId,
        'confidence': item.confidence,
        'crop': item.crop,
        'province': item.province,
        'municipality': item.municipality,
        'createdAt': item.createdAt.toIso8601String(),
      };
}
