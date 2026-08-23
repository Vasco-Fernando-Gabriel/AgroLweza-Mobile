import 'package:agrolweza_app/history_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migracao de registos gravados antes do id', () {
    // Formato exato que ja existe nos telemoveis em campo: sem 'id'.
    final legacy = {
      'diagnosisId': 'cassava_mosaic',
      'confidence': 0.87,
      'crop': 'mandioca',
      'createdAt': '2026-08-20T10:00:00.000',
      'syncStatus': 'pending',
    };

    test('nao descarta o registo e atribui um id', () {
      final item = HistoryItem.fromJson(Map<String, dynamic>.from(legacy));
      expect(item.id, isNotEmpty);
      expect(item.diagnosisId, 'cassava_mosaic');
      expect(item.confidence, 0.87);
      expect(item.syncStatus, SyncStatus.pending);
    });

    test('o id derivado e estavel entre leituras', () {
      final a = HistoryItem.fromJson(Map<String, dynamic>.from(legacy));
      final b = HistoryItem.fromJson(Map<String, dynamic>.from(legacy));
      expect(a.id, b.id);
    });
  });

  test('round-trip preserva o id', () {
    final original = HistoryItem(
      id: HistoryItem.newId(),
      diagnosisId: 'healthy',
      confidence: 0.91,
      crop: 'mandioca',
      createdAt: DateTime.parse('2026-08-21T09:34:00.000'),
      syncStatus: SyncStatus.pending,
    );
    final restored = HistoryItem.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.isSynced, isFalse);
  });

  test('newId nao colide em geracoes seguidas', () {
    final ids = List.generate(500, (_) => HistoryItem.newId());
    expect(ids.toSet().length, 500);
  });

  test('copyWith so muda o estado e mantem a chave de idempotencia', () {
    final item = HistoryItem(
      id: 'dx-fixo',
      diagnosisId: 'healthy',
      confidence: 0.9,
      crop: 'mandioca',
      createdAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );
    final synced = item.copyWith(syncStatus: SyncStatus.synced);
    expect(synced.id, 'dx-fixo');
    expect(synced.isSynced, isTrue);
  });
}
