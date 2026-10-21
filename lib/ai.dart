import 'dart:convert';

import 'package:http/http.dart' as http;

import 'idx_runner.dart';
import 'settings.dart';

/// Search1API client (user's own key). Defensive parsing: fields vary a bit
/// between endpoints, so extract whatever list of results comes back.
class S1Client {
  final String apiKey;
  S1Client(this.apiKey);

  Future<List<Map<String, String>>> _post(String path, String query) async {
    final resp = await http
        .post(
          Uri.parse('${AppSettings.s1Base}$path'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'query': query, 'max_results': 5}),
        )
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw Exception('Search1API HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    final out = <Map<String, String>>[];
    void harvest(dynamic node) {
      if (node is List) {
        for (final e in node) {
          if (e is Map) {
            final title = '${e['title'] ?? ''}';
            final link = '${e['link'] ?? e['url'] ?? ''}';
            final text = '${e['snippet'] ?? e['content'] ?? e['description'] ?? ''}';
            if (title.isNotEmpty || link.isNotEmpty) {
              out.add({'title': title, 'link': link, 'text': text});
            }
          }
        }
      } else if (node is Map) {
        for (final k in ['results', 'organic_results', 'news', 'data']) {
          if (node[k] is List) harvest(node[k]);
        }
      }
    }

    harvest(body);
    return out;
  }

  Future<List<Map<String, String>>> search(String query) => _post('/search', query);
  Future<List<Map<String, String>>> news(String query) => _post('/news', query);
}

class ChatMessage {
  final String role; // user | assistant
  final String text;
  ChatMessage(this.role, this.text);
}

/// GripHub Router chat with a tool-calling loop. The model may only use
/// numbers that come back from tools; the system prompt enforces that and
/// the tools are the only data source.
class AiAnalyst {
  static const systemPrompt = '''
Kamu adalah BandarAI, analis saham pribadi untuk Bursa Efek Indonesia (IDX/IHSG), berbahasa Indonesia yang lugas dan hangat.

ATURAN KERAS:
1. Semua angka (harga, persen, rasio, nilai transaksi, persentase kepemilikan) HANYA boleh berasal dari hasil tool pada percakapan ini. Jangan pernah mengarang atau mengingat angka dari pengetahuanmu.
2. Jika data yang dibutuhkan belum ada, panggil tool yang sesuai dulu, baru jawab.
3. Bedakan tegas antara FAKTA dari data dan INTERPRETASI/pendapatmu. Interpretasi selalu diberi awalan seperti "Interpretasi:" atau "Artinya:".
4. Untuk pertanyaan "kenapa saham X bergerak", gabungkan data idx (harga, foreign/bandar, berita idx) dengan s1_search berita web bila tool itu tersedia, dan sebutkan sumber beritanya.
5. Jawaban ringkas tapi lengkap: mulai dari kesimpulan, lalu bukti angka, lalu interpretasi. Gunakan daftar poin bila membantu.
6. Akhiri analisis saham dengan satu baris: "Ini analisis & edukasi, bukan nasihat investasi."
7. Tanggal/waktu acuan adalah waktu Jakarta (WIB). Data harga dari sumber gratis bersifat delayed; sebutkan bila relevan.
''';

  static List<Map<String, dynamic>> toolSchemas({required bool withS1}) {
    Map<String, dynamic> fn(String name, String desc,
        Map<String, dynamic> props, List<String> required) {
      return {
        'type': 'function',
        'function': {
          'name': name,
          'description': desc,
          'parameters': {
            'type': 'object',
            'properties': props,
            'required': required,
          },
        },
      };
    }

    final tools = <Map<String, dynamic>>[
      fn('idx_quote', 'Harga terkini (delayed) satu/lebih emiten IDX.',
          {'symbols': {'type': 'string', 'description': 'Kode emiten, pisahkan koma. Contoh: BBCA,BBRI'}}, ['symbols']),
      fn('idx_brief', 'Ringkasan lengkap satu emiten: quote, verdict fundamental, teknikal, returns vs IHSG, dividen, pemilik >1%, berita, dan poin-poin kunci berbahasa polos.',
          {'symbol': {'type': 'string', 'description': 'Kode emiten, contoh: BBCA'}}, ['symbol']),
      fn('idx_bandar', 'Analisis bandarmologi: akumulasi/distribusi top broker (IPOT), sinyal, fase, rata-rata harga bandar, foreign net.',
          {
            'symbols': {'type': 'string', 'description': 'Kode emiten, pisahkan koma'},
            'period': {'type': 'string', 'description': 'Rentang: 1d, 1w, 1m, 3m. Default 1w.'}
          }, ['symbols']),
      fn('idx_bandar_screen', 'Saring 100 saham teraktif berdasarkan perilaku bandar. Preset: big-accumulation, accumulation, distribution, big-distribution, quiet-accumulation, quiet-distribution, foreign-accumulation, below-bandar.',
          {'preset': {'type': 'string'}}, ['preset']),
      fn('idx_screen', 'Screener saham IDX dengan filter seperti "pe<15,roe>15,div>5,sector=financial". Kunci umum: pe, pb, roe, div, mcap, price, chg.',
          {'filter': {'type': 'string'}}, ['filter']),
      fn('idx_news', 'Berita Kontan & CNBC Indonesia. Dengan symbol: berita perusahaan itu dulu, lalu konteks pasar.',
          {'symbol': {'type': 'string', 'description': 'Opsional: kode emiten'}}, []),
      fn('idx_ownership', 'Pemegang saham di atas 1% sebuah emiten dari register KSEI (butuh impor data dulu; bila kosong, katakan datanya belum diimpor).',
          {'symbol': {'type': 'string'}}, ['symbol']),
      fn('idx_market', 'Gambaran pasar: IHSG, breadth, turnover, top gainers/losers, saham teraktif.', {}, []),
    ];
    if (withS1) {
      tools.add(fn('s1_search', 'Cari berita & konteks dari seluruh web (Search1API) — penyebab pergerakan, kabar emiten, konteks global. Hasil berisi judul + tautan sumber.',
          {'query': {'type': 'string', 'description': 'Kata kunci pencarian, sertakan nama/kode emiten dan kata seperti "saham", "turun", "naik", tanggal bila relevan'}}, ['query']));
      tools.add(fn('s1_news', 'Berita terbaru dari web (Search1API News) untuk sebuah topik/emiten.',
          {'query': {'type': 'string'}}, ['query']));
    }
    return tools;
  }

  static String _truncate(String s, [int max = 12000]) =>
      s.length <= max ? s : '${s.substring(0, max)}…[dipotong]';

  static Future<String> _runTool(String name, Map<String, dynamic> a) async {
    final idx = await IdxRunner.instance();
    dynamic data;
    switch (name) {
      case 'idx_quote':
        data = await idx.run(['stocks', 'quote', '${a['symbols']}']);
        break;
      case 'idx_brief':
        data = await idx.run(['stocks', 'brief', '${a['symbol']}'],
            timeout: const Duration(seconds: 150));
        break;
      case 'idx_bandar':
        data = await idx.run([
          'bandar', 'detect', '${a['symbols']}',
          if (a['period'] != null) ...['--period', '${a['period']}']
        ], timeout: const Duration(seconds: 150));
        break;
      case 'idx_bandar_screen':
        data = await idx.run(['bandar', 'screen', '--preset', '${a['preset']}'],
            timeout: const Duration(seconds: 240));
        break;
      case 'idx_screen':
        data = await idx.run(['stocks', 'screen', '-f', '${a['filter']}'],
            timeout: const Duration(seconds: 240));
        break;
      case 'idx_news':
        data = await idx.run([
          'stocks', 'news',
          if (a['symbol'] != null && '${a['symbol']}'.isNotEmpty) '${a['symbol']}'
        ]);
        break;
      case 'idx_ownership':
        data = await idx.run(['ownership', 'ticker', '${a['symbol']}']);
        break;
      case 'idx_market':
        data = await idx.run(['market', 'overview']);
        break;
      case 's1_search':
      case 's1_news':
        final key = await AppSettings.s1Key();
        if (key == null) return 'Tool web tidak tersedia: key Search1API belum diisi.';
        final s1 = S1Client(key);
        final results = name == 's1_search'
            ? await s1.search('${a['query']}')
            : await s1.news('${a['query']}');
        return _truncate(jsonEncode({'results': results}));
      default:
        return 'Tool tidak dikenal: $name';
    }
    return _truncate(jsonEncode(data));
  }

  /// Full chat turn: sends history + new user text, runs the tool loop,
  /// returns the assistant's final text. [onTool] reports each tool call
  /// about to run; [onPhase] reports loop phases ('model' before each
  /// model request) so the UI can show a detailed progress card.
  static Future<String> chat(List<ChatMessage> history, String userText,
      {void Function(String tool)? onTool,
      void Function(String phase)? onPhase}) async {
    final key = await AppSettings.griphubKey();
    if (key == null || key.isEmpty) {
      throw Exception('API key GripHub belum diisi. Buka tab Pengaturan dulu ya.');
    }
    var model = await AppSettings.model();
    final s1 = await AppSettings.s1Key();
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      for (final m in history)
        {'role': m.role, 'content': m.text},
      {'role': 'user', 'content': userText},
    ];
    model ??= await _firstModel(key);
    var s1Calls = 0;
    for (var round = 0; round < 6; round++) {
      onPhase?.call('model');
      final resp = await http
          .post(
            Uri.parse('${AppSettings.griphubBase}/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'tools': toolSchemas(withS1: s1 != null),
              'tool_choice': 'auto',
            }),
          )
          .timeout(const Duration(seconds: 180));
      if (resp.statusCode != 200) {
        throw Exception('GripHub HTTP ${resp.statusCode}: ${_truncate(resp.body, 300)}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final choice = (body['choices'] as List).first as Map<String, dynamic>;
      final msg = choice['message'] as Map<String, dynamic>;
      messages.add(msg);
      final calls = (msg['tool_calls'] as List?) ?? const [];
      if (calls.isEmpty) {
        return (msg['content'] as String?)?.trim().isNotEmpty == true
            ? msg['content'] as String
            : '(jawaban kosong dari model)';
      }
      for (final c in calls) {
        final f = (c as Map<String, dynamic>)['function'] as Map<String, dynamic>;
        final name = f['name'] as String;
        var args = <String, dynamic>{};
        try {
          args = jsonDecode(f['arguments'] as String? ?? '{}') as Map<String, dynamic>;
        } catch (_) {}
        onTool?.call(name);
        String result;
        if ((name == 's1_search' || name == 's1_news') && ++s1Calls > 3) {
          result = 'Batas 3 panggilan web per pertanyaan tercapai. Simpulkan dari data yang ada.';
        } else {
          try {
            result = await _runTool(name, args);
          } catch (e) {
            result = 'Tool $name gagal: $e';
          }
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': c['id'],
          'content': result,
        });
      }
    }
    throw Exception('Model terlalu banyak memanggil tool; coba pertanyaan yang lebih spesifik.');
  }

  static Future<List<String>> listModels(String key) async {
    final resp = await http.get(
      Uri.parse('${AppSettings.griphubBase}/models'),
      headers: {'Authorization': 'Bearer $key'},
    ).timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw Exception('GripHub HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? const [];
    return [for (final m in data) '${(m as Map)['id']}'];
  }

  static Future<String> _firstModel(String key) async {
    final models = await listModels(key);
    if (models.isEmpty) throw Exception('Katalog model GripHub kosong.');
    return models.first;
  }
}
