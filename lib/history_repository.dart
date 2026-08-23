import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'history_item.dart';

const _storageKey = 'agrolweza-history';

/// Persistência local do histórico. Equivalente ao localStorage do protótipo.
class HistoryRepository {
  Future<List<HistoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final items = <HistoryItem>[];
    for (final e in list) {
      try {
        items.add(HistoryItem.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        // Entrada de um schema antigo (pré-integração do modelo real). Ignora.
      }
    }
    return items;
  }

  Future<void> save(List<HistoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}
