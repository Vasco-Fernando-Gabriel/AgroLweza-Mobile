import 'dart:convert';
import 'dart:io';

import 'package:agrolweza_app/history_item.dart';
import 'package:agrolweza_app/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryItem _item({String id = 'dx-teste'}) => HistoryItem(
      id: id,
      diagnosisId: 'cassava_mosaic',
      confidence: 0.87,
      crop: 'mandioca',
      province: 'Malanje',
      municipality: 'Cacuso',
      createdAt: DateTime.parse('2026-08-20T10:00:00.000'),
      syncStatus: SyncStatus.pending,
    );

void main() {
  late HttpServer server;
  // Preenchido pelo handler a cada pedido recebido, para inspecao nos testes.
  Map<String, dynamic>? lastBody;
  String? lastIdempotencyKey;
  // Codigo que o proximo pedido deve devolver (o teste controla).
  late int nextStatus;

  Uri endpoint() =>
      Uri.parse('http://${server.address.host}:${server.port}/v1/diagnosticos');

  HttpSyncTransport transport({Duration? timeout}) => HttpSyncTransport(
        endpoint: endpoint(),
        timeout: timeout ?? const Duration(seconds: 5),
      );

  setUp(() async {
    lastBody = null;
    lastIdempotencyKey = null;
    nextStatus = HttpStatus.created;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      lastIdempotencyKey = req.headers.value('Idempotency-Key');
      final raw = await utf8.decoder.bind(req).join();
      lastBody = jsonDecode(raw) as Map<String, dynamic>;
      req.response.statusCode = nextStatus;
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('2xx e sucesso e envia os metadados + chave de idempotencia', () async {
    nextStatus = HttpStatus.created;
    final outcome = await transport().send(_item(id: 'dx-abc'));

    expect(outcome, SyncOutcome.success);
    expect(lastIdempotencyKey, 'dx-abc');
    expect(lastBody, {
      'id': 'dx-abc',
      'diagnosisId': 'cassava_mosaic',
      'confidence': 0.87,
      'crop': 'mandioca',
      'province': 'Malanje',
      'municipality': 'Cacuso',
      'createdAt': '2026-08-20T10:00:00.000',
    });
  });

  test('409 Conflict conta como sucesso (idempotente, ja existia)', () async {
    nextStatus = HttpStatus.conflict;
    expect(await transport().send(_item()), SyncOutcome.success);
  });

  test('5xx e falha recuperavel', () async {
    nextStatus = HttpStatus.internalServerError;
    expect(await transport().send(_item()), SyncOutcome.failure);
  });

  test('4xx (fora do 409) e falha', () async {
    nextStatus = HttpStatus.badRequest;
    expect(await transport().send(_item()), SyncOutcome.failure);
  });

  test('destino inacessivel e falha, nao lanca excecao', () async {
    // Fecha o servidor antes de enviar: a ligacao e recusada.
    final t = transport(timeout: const Duration(milliseconds: 500));
    await server.close(force: true);
    expect(await t.send(_item()), SyncOutcome.failure);
    // Reabre para o tearDown fechar sem erro.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
}
