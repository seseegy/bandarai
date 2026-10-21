import 'package:flutter/material.dart';

import '../ai.dart';
import '../idx_runner.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _market;
  List<dynamic> _watchQuotes = [];
  String? _briefing;
  bool _loading = true;
  bool _briefingBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final idx = await IdxRunner.instance();
    try {
      final m = await idx.run(['market', 'overview']);
      if (m is Map) {
        if (mounted) {
          setState(() => _market = m.cast<String, dynamic>());
        }
      }
      final watch = await AppSettings.watchlist();
      if (watch.isNotEmpty) {
        final q = await idx.run(['stocks', 'quote', watch.join(',')]);
        if (mounted && q is List) setState(() => _watchQuotes = q);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _makeBriefing() async {
    setState(() => _briefingBusy = true);
    try {
      final watch = await AppSettings.watchlist();
      final text = await AiAnalyst.chat(const [],
          'Buat briefing pasar IDX hari ini untukku. Watchlist-ku: ${watch.join(', ')}. '
          'Pakai tool: gambaran pasar, quote watchlist, dan bandar screen quiet-accumulation. '
          'Format: 3-5 poin singkat — kondisi IHSG & asing, watchlist yang menonjol, dan saham yang sedang diakumulasi diam-diam.');
      if (mounted) setState(() => _briefing = text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => _briefingBusy = false);
  }

  void _search() async {
    final sym = await showDialog<String>(
      context: context,
      builder: (_) => const _SymbolDialog(),
    );
    if (sym != null && sym.isNotEmpty && mounted) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StockScreen(sym.toUpperCase())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.candlestick_chart_rounded, color: AppColors.primary),
          SizedBox(width: 8),
          Text('BandarAI',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Cari emiten',
            onPressed: _search,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _market == null
              ? LoadError(_error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final m = _market ?? {};
    final index = (m['index'] as Map?)?.cast<String, dynamic>() ??
        (m['ihsg'] as Map?)?.cast<String, dynamic>();
    final gainers = _firstList(m, ['top_gainers', 'gainers']);
    final losers = _firstList(m, ['top_losers', 'losers']);
    final active = _firstList(m, ['most_traded', 'top_value', 'most_active']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (index != null)
          SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('IHSG',
                          style: TextStyle(
                              color: AppColors.mutedForeground, fontSize: 12)),
                      Text(fmtNum((index['close'] as num?) ?? (index['price'] as num?),
                              dec: 2),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Text(fmtPct(index['change_pct'] as num?),
                    style: TextStyle(
                        color: pctColor(index['change_pct'] as num?),
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        SectionCard(
          title: 'BRIEFING AI',
          child: _briefing == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Ringkasan pasar + watchlist + akumulasi diam-diam, ditulis analis AI dari data asli.',
                        style: TextStyle(
                            color: AppColors.mutedForeground, fontSize: 13)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _briefingBusy ? null : _makeBriefing,
                      icon: _briefingBusy
                          ? const SizedBox(
                              width: 15, height: 15,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.background))
                          : const Icon(Icons.auto_awesome_rounded, size: 17),
                      label: Text(_briefingBusy
                          ? 'Analis sedang bekerja…'
                          : 'Buat briefing hari ini'),
                    ),
                  ],
                )
              : SelectableText(_briefing!,
                  style: const TextStyle(fontSize: 13.5, height: 1.5)),
        ),
        if (_watchQuotes.isNotEmpty) ...[
          const _SectionTitle('Watchlist'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              children: [
                for (final q in _watchQuotes)
                  QuoteRow((q as Map).cast<String, dynamic>(),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              StockScreen('${q['symbol']}')))),
              ],
            ),
          ),
        ],
        if (gainers.isNotEmpty) ...[
          const _SectionTitle('Top Gainers'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(children: [
              for (final q in gainers.take(5))
                QuoteRow((q as Map).cast<String, dynamic>(),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StockScreen('${q['symbol']}')))),
            ]),
          ),
        ],
        if (losers.isNotEmpty) ...[
          const _SectionTitle('Top Losers'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(children: [
              for (final q in losers.take(5))
                QuoteRow((q as Map).cast<String, dynamic>(),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StockScreen('${q['symbol']}')))),
            ]),
          ),
        ],
        if (active.isNotEmpty) ...[
          const _SectionTitle('Paling Aktif'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(children: [
              for (final q in active.take(5))
                QuoteRow((q as Map).cast<String, dynamic>(),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StockScreen('${q['symbol']}')))),
            ]),
          ),
        ],
        const Disclaimer(),
      ],
    );
  }

  static List<dynamic> _firstList(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m[k] is List) return m[k] as List;
    }
    return const [];
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14.5)),
    );
  }
}

class _SymbolDialog extends StatefulWidget {
  const _SymbolDialog();
  @override
  State<_SymbolDialog> createState() => _SymbolDialogState();
}

class _SymbolDialogState extends State<_SymbolDialog> {
  final _c = TextEditingController();
  List<dynamic> _results = [];
  bool _busy = false;

  Future<void> _go() async {
    final q = _c.text.trim();
    if (q.isEmpty) return;
    if (q.length == 4 && !q.contains(' ')) {
      Navigator.of(context).pop(q.toUpperCase());
      return;
    }
    setState(() => _busy = true);
    try {
      final idx = await IdxRunner.instance();
      final r = await idx.run(['stocks', 'list', '--search', q]);
      if (mounted && r is List) setState(() => _results = r);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cari emiten'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _c,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  hintText: 'Kode (BBCA) atau nama (bank)…'),
              onSubmitted: (_) => _go(),
            ),
            if (_busy) const LinearProgressIndicator(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _results.take(12))
                    ListTile(
                      dense: true,
                      title: Text('${(r as Map)['symbol']}'),
                      subtitle: Text('${r['name'] ?? ''}'),
                      onTap: () =>
                          Navigator.of(context).pop('${r['symbol']}'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        FilledButton(onPressed: _go, child: const Text('Buka')),
      ],
    );
  }
}

/// Helper so HomeScreen's chat import stays used for the briefing engine.
typedef ChatEngine = AiAnalyst;
typedef ChatScreenRef = ChatScreen;
