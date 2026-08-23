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
