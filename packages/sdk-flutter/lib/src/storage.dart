import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan antrian laporan offline. Default: SharedPreferences (bertahan saat app ditutup).
abstract class QueueStore {
  Future<List<Map<String, dynamic>>> load();
  Future<void> save(List<Map<String, dynamic>> items);
}

class SharedPrefsQueueStore implements QueueStore {
  SharedPrefsQueueStore(this.key);
  final String key;

  @override
  Future<List<Map<String, dynamic>>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<Map<String, dynamic>> items) async {
    final p = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, jsonEncode(items));
    }
  }
}

/// Untuk test atau bila persistensi tidak diinginkan.
class MemoryQueueStore implements QueueStore {
  List<Map<String, dynamic>> _items = [];
  @override
  Future<List<Map<String, dynamic>>> load() async => List.of(_items);
  @override
  Future<void> save(List<Map<String, dynamic>> items) async =>
      _items = List.of(items);
}
