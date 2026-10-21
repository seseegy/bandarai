import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Runs the bundled `idx` binary (packaged as libidx.so in jniLibs) and
/// returns its parsed JSON envelope. All idx state (cache, config, KSEI
/// SQLite) lives in app-private storage via IDX_* env vars.
class IdxException implements Exception {
  final int exitCode;
  final String message;
  IdxException(this.exitCode, this.message);
  @override
  String toString() => message;
}

class IdxRunner {
  static const _channel = MethodChannel('bandarai/native');
  static IdxRunner? _instance;
  static Future<IdxRunner> instance() async {
    if (_instance != null) return _instance!;
    final libDir = await _channel.invokeMethod<String>('nativeLibraryDir');
    final support = await getApplicationSupportDirectory();
    final base = Directory('${support.path}/idx');
    for (final sub in ['cache', 'config', 'data']) {
      await Directory('${base.path}/$sub').create(recursive: true);
    }
    _instance = IdxRunner._('$libDir/libidx.so', base.path);
    return _instance!;
  }

  final String binaryPath;
  final String baseDir;
  IdxRunner._(this.binaryPath, this.baseDir);

  bool get binaryExists => File(binaryPath).existsSync();

  Map<String, String> get _env => {
        'HOME': baseDir,
        'IDX_CACHE_DIR': '$baseDir/cache',
        'IDX_CONFIG': '$baseDir/config/config.toml',
        'IDX_OWNERSHIP_DB': '$baseDir/data/ownership.sqlite',
        'IDX_WATCHLIST': '$baseDir/data/watchlist.txt',
        'NO_COLOR': '1',
        'IDX_PROGRESS': 'never',
      };

  /// Runs idx with [args]; returns the envelope's `data` payload.
  /// Throws [IdxException] with idx's own error message on failure.
  Future<dynamic> run(List<String> args,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final result = await Process.run(binaryPath, ['-o', 'json', ...args],
            environment: _env, includeParentEnvironment: true)
        .timeout(timeout);
    final out = result.stdout as String;
    final err = (result.stderr as String).trim();
    Map<String, dynamic>? envelope;
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map<String, dynamic>) envelope = decoded;
    } catch (_) {}
    if (result.exitCode != 0 || envelope == null) {
      var msg = err;
      if (envelope != null && envelope['error'] is Map) {
        msg = '${(envelope['error'] as Map)['message'] ?? err}';
      }
      if (msg.isEmpty) msg = 'idx gagal (kode ${result.exitCode})';
      throw IdxException(result.exitCode, msg);
    }
    if (envelope['error'] != null) {
      final e = envelope['error'];
      throw IdxException(result.exitCode,
          e is Map ? '${e['message'] ?? e}' : '$e');
    }
    return envelope['data'];
  }

  /// Runs idx and returns the raw envelope (schema/provider/cached info).
  Future<Map<String, dynamic>> runEnvelope(List<String> args,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final result = await Process.run(binaryPath, ['-o', 'json', ...args],
            environment: _env, includeParentEnvironment: true)
        .timeout(timeout);
    final out = result.stdout as String;
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw IdxException(result.exitCode,
        (result.stderr as String).trim().isEmpty
            ? 'output idx tidak valid'
            : (result.stderr as String).trim());
  }

  Future<String> version() async {
    final result = await Process.run(binaryPath, ['version'],
        environment: _env, includeParentEnvironment: true);
    return (result.stdout as String).trim().split('\n').first;
  }
}
