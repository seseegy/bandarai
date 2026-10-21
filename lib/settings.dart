import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Semua pengaturan user tinggal di secure storage HP ini.
///
/// Dulu pilihan model + watchlist disimpan via plugin shared_preferences,
/// tapi build APK-nya terbukti rusak di HP user (NoSuchMethodError dari
/// kode native plugin saat runtime) — makanya dipindah ke sini sekalian.
/// Secure storage ini yang sama dengan tempat API key, dan terbukti jalan.
class AppSettings {
  static const _storage = FlutterSecureStorage();
  static const _kGripKey = 'griphub_api_key';
  static const _kS1Key = 's1_api_key';
  static const _kModel = 'griphub_model';
  static const _kWatch = 'watchlist';
  static const griphubBase = 'https://griphubrouter.web.id/v1';
  static const s1Base = 'https://api.search1api.com';

  static Future<String?> griphubKey() => _storage.read(key: _kGripKey);
  static Future<String?> s1Key() => _storage.read(key: _kS1Key);
  static Future<void> setGriphubKey(String? v) => v == null || v.isEmpty
      ? _storage.delete(key: _kGripKey)
      : _storage.write(key: _kGripKey, value: v.trim());
  static Future<void> setS1Key(String? v) => v == null || v.isEmpty
      ? _storage.delete(key: _kS1Key)
      : _storage.write(key: _kS1Key, value: v.trim());

  static Future<String?> model() => _storage.read(key: _kModel);
  static Future<void> setModel(String? v) => v == null || v.isEmpty
      ? _storage.delete(key: _kModel)
      : _storage.write(key: _kModel, value: v);

  static const _defaultWatch = ['BBCA', 'BBRI', 'TLKM', 'GOTO'];

  static Future<List<String>> watchlist() async {
    try {
      final raw = await _storage.read(key: _kWatch);
      if (raw == null || raw.isEmpty) return List.of(_defaultWatch);
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => '$e').toList();
      }
    } catch (_) {
      // Penyimpanan tak terbaca — pakai daftar bawaan, jangan sampai
      // layar mana pun nyangkut gara-gara ini.
    }
    return List.of(_defaultWatch);
  }

  static Future<void> setWatchlist(List<String> v) =>
      _storage.write(key: _kWatch, value: jsonEncode(v));

  // --- Riwayat chat analis (persisten, JSON mentah) ---
  // Format JSON dikelola layar chat; di sini cuma disimpan apa adanya.
  static const _kChat = 'chat_history_v1';

  static Future<String?> chatHistoryJson() => _storage.read(key: _kChat);
  static Future<void> saveChatHistoryJson(String json) =>
      _storage.write(key: _kChat, value: json);
  static Future<void> clearChatHistory() => _storage.delete(key: _kChat);
}
