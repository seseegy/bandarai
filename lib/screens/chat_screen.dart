import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../ai.dart';
import '../settings.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  final String? initialQuestion;

  /// Tab ini sedang tampil atau tidak (di RootShell semua tab hidup terus
  /// di IndexedStack, jadi status key + riwayat harus dicek ulang saat
  /// tab aktif lagi).
  final bool isActive;

  const ChatScreen({super.key, this.initialQuestion, this.isActive = true});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _busy = false;
  bool _keyMissing = false;

  // Pelacakan proses analis untuk kartu progres detail.
  final List<String> _doneSteps = [];
  String? _currentStep;
  bool _sawTool = false;
  DateTime? _startedAt;
  Timer? _ticker;
  int _elapsedSec = 0;

  static const _suggestions = [
    'Analisis BBCA',
    'Siapa yang lagi akumulasi diam-diam?',
    'Kenapa GOTO bergerak hari ini?',
    'Carikan bank PE di bawah 10, dividen di atas 5%',
  ];

  static const _toolLabels = {
    'idx_quote': 'Mengambil harga emiten',
    'idx_brief': 'Menyusun briefing emiten',
    'idx_bandar': 'Menganalisis bandarmologi',
    'idx_bandar_screen': 'Memindai radar bandar',
    'idx_screen': 'Menyaring emiten',
    'idx_news': 'Mengambil berita emiten',
    'idx_ownership': 'Memeriksa kepemilikan KSEI',
    'idx_market': 'Mengambil data pasar & IHSG',
    's1_search': 'Mencari konteks di web',
    's1_news': 'Mencari berita di web',
  };

  @override
  void initState() {
    super.initState();
    _refreshKey();
    _loadHistory();
    if (widget.initialQuestion != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _send(widget.initialQuestion!));
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tab baru saja dibuka lagi — key bisa saja baru disimpan user,
    // dan riwayat bisa saja bertambah dari layar chat lain (mis. dari
    // halaman emiten). Segarkan keduanya.
    if (widget.isActive && !oldWidget.isActive) {
      _refreshKey();
      if (!_busy) _loadHistory();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshKey() async {
    final k = await AppSettings.griphubKey();
    if (mounted) setState(() => _keyMissing = k == null || k.isEmpty);
  }

  // ---------- Persistensi riwayat ----------

  Future<void> _loadHistory() async {
    try {
      final raw = await AppSettings.chatHistoryJson();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <ChatMessage>[
        for (final e in decoded)
          if (e is Map && e['t'] != null)
            ChatMessage('${e['r'] ?? 'user'}', '${e['t']}'),
      ];
      if (!mounted || _busy) return;
      if (loaded.length != _messages.length) {
        setState(() {
          _messages
            ..clear()
            ..addAll(loaded);
        });
        _jump();
      }
    } catch (_) {
      // Riwayat rusak/tak terbaca — mulai dari kosong saja, jangan crash.
    }
  }

  Future<void> _persist() async {
    try {
      final tail =
          _messages.length > 100 ? _messages.sublist(_messages.length - 100) : _messages;
      await AppSettings.saveChatHistoryJson(jsonEncode(
          [for (final m in tail) {'r': m.role, 't': m.text}]));
    } catch (_) {
      // Gagal menyimpan riwayat bukan alasan chat ikut gagal.
    }
  }

  Future<void> _clearHistory() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus riwayat chat?'),
        content: const Text(
            'Semua percakapan dengan analis di HP ini akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yes != true) return;
    await AppSettings.clearChatHistory();
    if (mounted) setState(_messages.clear);
  }

  // ---------- Proses analis ----------

  void _finishStep() {
    if (_currentStep != null) {
      _doneSteps.add(_currentStep!);
      _currentStep = null;
    }
  }

  void _onPhase(String phase) {
    if (!mounted) return;
    setState(() {
      if (phase == 'model') {
        if (!_sawTool && _doneSteps.isEmpty && _currentStep == null) {
          _currentStep = 'Menghubungi model AI';
        } else {
          _finishStep();
          _currentStep = 'Menyusun jawaban dari data';
        }
      }
    });
    _jump();
  }

  void _onTool(String name) {
    if (!mounted) return;
    setState(() {
      _sawTool = true;
      _finishStep();
      _currentStep = _toolLabels[name] ?? 'Menjalankan $name';
    });
    _jump();
  }

  String get _elapsedLabel {
    final m = _elapsedSec ~/ 60;
    final s = (_elapsedSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _busy) return;
    await _refreshKey();
    _input.clear();
    final history = _messages.length > 20
        ? _messages.sublist(_messages.length - 20)
        : List<ChatMessage>.of(_messages);
    setState(() {
      _messages.add(ChatMessage('user', q));
      _busy = true;
      _doneSteps.clear();
      _currentStep = null;
      _sawTool = false;
      _startedAt = DateTime.now();
      _elapsedSec = 0;
    });
    _persist();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _startedAt != null) {
        setState(() =>
            _elapsedSec = DateTime.now().difference(_startedAt!).inSeconds);
      }
    });
    _jump();
    try {
      final answer = await AiAnalyst.chat(
        history,
        q,
        onTool: _onTool,
        onPhase: _onPhase,
      );
      if (!mounted) return;
      setState(() => _messages.add(ChatMessage('assistant', answer)));
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _messages.add(ChatMessage('assistant', 'Maaf, ada kendala: $e')));
    } finally {
      _ticker?.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _currentStep = null;
          _startedAt = null;
        });
      }
    }
    _persist();
    _jump();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  void _copy(ChatMessage m) {
    Clipboard.setData(ClipboardData(text: m.text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pesan disalin.'), duration: Duration(seconds: 2)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Analis',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Hapus riwayat chat',
            onPressed: _messages.isEmpty || _busy ? null : _clearHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_keyMissing)
            Material(
              color: AppColors.down.withValues(alpha: 0.15),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Row(children: [
                  Icon(Icons.key_off_outlined, size: 18, color: AppColors.down),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'API key GripHub belum diisi — buka Pengaturan (ikon gerigi di Beranda) dulu ya.',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: _messages.isEmpty && !_busy
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) return _processCard();
                      return _messageBlock(_messages[i]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(
                        hintText: 'Tanya saham apa saja…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : () => _send(_input.text),
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.candlestick_chart_rounded,
            size: 52, color: AppColors.primary),
        const SizedBox(height: 14),
        const Text('Halo, aku analis saham pribadimu.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'Semua jawabanku berpijak data asli dari binary idx di HP ini — harga, bandar, kepemilikan KSEI — plus berita web bila key Search1API terisi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s), onPressed: () => _send(s)),
          ],
        ),
      ],
    );
  }

  Widget _processCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 9),
            const Text('Analis bekerja',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const Spacer(),
            Text(_elapsedLabel,
                style: const TextStyle(
                    color: AppColors.mutedForeground, fontSize: 12)),
          ]),
          for (final s in _doneSteps)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    size: 15, color: AppColors.up),
                const SizedBox(width: 8),
                Text(s,
                    style: const TextStyle(
                        color: AppColors.mutedForeground, fontSize: 12.5)),
              ]),
            ),
          if (_currentStep != null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 9),
                Text('$_currentStep…',
                    style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _messageBlock(ChatMessage m) {
    final isUser = m.role == 'user';
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
          decoration: BoxDecoration(
            color: isUser ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isUser ? 14 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 14),
            ),
            border:
                isUser ? null : Border.all(color: AppColors.border, width: 0.6),
          ),
          child: isUser
              ? SelectableText(
                  m.text,
                  style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 14,
                    height: 1.45,
                  ),
                )
              : MarkdownBody(
                  data: m.text,
                  selectable: true,
                  styleSheet: _mdStyle(),
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
          child: InkWell(
            onTap: () => _copy(m),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded,
                      size: 13, color: AppColors.mutedForeground),
                  SizedBox(width: 4),
                  Text('Salin',
                      style: TextStyle(
                          color: AppColors.mutedForeground, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  MarkdownStyleSheet _mdStyle() {
    const base = TextStyle(
        color: AppColors.foreground, fontSize: 14, height: 1.45);
    return MarkdownStyleSheet(
      p: base,
      h1: base.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
      h2: base.copyWith(fontSize: 15.5, fontWeight: FontWeight.w800),
      h3: base.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
      strong: base.copyWith(fontWeight: FontWeight.w800),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(color: AppColors.primary),
      code: base.copyWith(
        fontSize: 12.5,
        fontFamily: 'monospace',
        backgroundColor: AppColors.background,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      blockquote: base.copyWith(color: AppColors.mutedForeground),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      tableHead: base.copyWith(fontWeight: FontWeight.w800, fontSize: 13),
      tableBody: base.copyWith(fontSize: 13),
      tableBorder: TableBorder.all(color: AppColors.border, width: 0.6),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
      ),
    );
  }
}
