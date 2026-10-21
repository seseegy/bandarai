import 'package:flutter/material.dart';

import '../idx_runner.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/price_chart.dart';
import 'chat_screen.dart';

class StockScreen extends StatefulWidget {
  final String symbol;
  const StockScreen(this.symbol, {super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  Map<String, dynamic>? _brief;
  Map<String, dynamic>? _bandar;
  dynamic _ownership;
  String? _error;
  bool _loading = true;
  bool _importing = false;
  bool _inWatch = false;

  String get sym => widget.symbol.toUpperCase();

  @override
  void initState() {
    super.initState();
    AppSettings.watchlist()
        .then((w) => mounted ? setState(() => _inWatch = w.contains(sym)) : null);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final idx = await IdxRunner.instance();
    try {
      final brief = await idx.run(['stocks', 'brief', sym],
          timeout: const Duration(seconds: 150));
      if (!mounted) return;
      setState(() {
        _brief = (brief as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
    // Bandar + ownership load independently; failures are non-fatal.
    try {
      final b = await idx.run(['bandar', 'detect', sym],
          timeout: const Duration(seconds: 150));
      if (mounted && b is Map) {
        setState(() => _bandar = b.cast<String, dynamic>());
      }
    } catch (_) {}
    try {
      final o = await idx.run(['ownership', 'ticker', sym]);
      if (mounted) setState(() => _ownership = o);
    } catch (_) {}
  }

  Future<void> _toggleWatch() async {
    final w = await AppSettings.watchlist();
    if (w.contains(sym)) {
      w.remove(sym);
    } else {
      w.add(sym);
    }
    await AppSettings.setWatchlist(w);
    if (mounted) setState(() => _inWatch = w.contains(sym));
  }

  Future<void> _importKsei() async {
    setState(() => _importing = true);
    try {
      final idx = await IdxRunner.instance();
      await idx.run(['ownership', 'import', '--latest'],
          timeout: const Duration(minutes: 10));
      final o = await idx.run(['ownership', 'ticker', sym]);
      if (mounted) setState(() => _ownership = o);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Impor KSEI gagal: $e')));
      }
    }
    if (mounted) setState(() => _importing = false);
  }

  void _askAi() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Chat Analis')),
        body: ChatScreen(initialQuestion: 'Analisis lengkap $sym untukku'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(sym),
        actions: [
          IconButton(
            icon: Icon(_inWatch ? Icons.star : Icons.star_border),
            color: _inWatch ? AppColors.primary : null,
            tooltip: _inWatch ? 'Hapus dari watchlist' : 'Tambah ke watchlist',
            onPressed: _toggleWatch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(_error!, onRetry: _load)
              : _body(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: FilledButton.icon(
            onPressed: _askAi,
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: const Text('Jelaskan pakai AI'),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final b = _brief!;
    final quote = (b['quote'] as Map?)?.cast<String, dynamic>() ?? {};
    final pct = quote['change_pct'] as num?;
    final keyPoints = (b['key_points'] as List?) ?? const [];
    final bandarRows = _bandar?['rows'] ?? _bandar?['results'];
    final bandarHeadline = _bandar?['headline'] ?? _bandar?['summary'];
    final owners = _ownership is Map
        ? ((_ownership as Map)['holders'] as List?)
        : (_ownership is List ? _ownership as List : null);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${b['name'] ?? sym}',
              style: const TextStyle(
                  color: AppColors.mutedForeground, fontSize: 13)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtNum(quote['price']),
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${fmtNum(quote['change'])} (${fmtPct(pct)})',
                  style: TextStyle(
                      color: pctColor(pct),
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Vol ${fmtBig((quote['volume'] as num?))} · Mkt cap ${fmtBig((quote['market_cap'] as num?))} · P/E ${quote['pe_trailing'] != null ? (quote['pe_trailing'] as num).toStringAsFixed(1) : '-'} · Div ${fmtPct(quote['dividend_yield_pct'] as num?, sign: false)}',
            style: const TextStyle(
                color: AppColors.mutedForeground, fontSize: 12),
          ),
          const SizedBox(height: 16),
          PriceChartSection(symbol: sym),
          if (keyPoints.isNotEmpty)
            SectionCard(
              title: 'POIN KUNCI',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in keyPoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(color: AppColors.primary)),
                          Expanded(child: Text('$p',
                              style: const TextStyle(fontSize: 13, height: 1.4))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_bandar != null)
            SectionCard(
              title: 'BANDAR (1 MINGGU)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bandarHeadline != null)
                    Text('$bandarHeadline',
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                  if (bandarRows is List && bandarRows.isNotEmpty)
                    ScalarRows((bandarRows.first as Map).cast<String, dynamic>()),
                  if (bandarHeadline == null && bandarRows == null)
                    ScalarRows(_bandar!),
                ],
              ),
            ),
          SectionCard(
            title: 'PEMILIK DI ATAS 1% (KSEI)',
            child: owners == null || owners.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Data kepemilikan belum diimpor di HP ini.',
                          style: TextStyle(
                              color: AppColors.mutedForeground, fontSize: 13)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _importing ? null : _importKsei,
                        icon: _importing
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 17),
                        label: Text(_importing
                            ? 'Mengimpor… (bisa beberapa menit)'
                            : 'Impor data KSEI terbaru'),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      for (final h in owners.take(10))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              '${(h as Map)['holder'] ?? h['name'] ?? ''}',
                              style: const TextStyle(fontSize: 13.5)),
                          subtitle: Text(
                              '${h['investor_type'] ?? ''} ${h['local_foreign'] ?? ''}',
                              style: const TextStyle(fontSize: 11.5)),
                          trailing: Text(
                            fmtPct((h['pct'] as num?) ?? (h['percent'] as num?),
                                sign: false),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                    ],
                  ),
          ),
          if (b['fundamentals'] is Map)
            SectionCard(
              title: 'FUNDAMENTAL',
              child: ScalarRows(
                  (b['fundamentals'] as Map).cast<String, dynamic>()),
            ),
          if (b['technical'] is Map)
            SectionCard(
              title: 'TEKNIKAL',
              child: ScalarRows(
                  (b['technical'] as Map).cast<String, dynamic>()),
            ),
          const Disclaimer(),
        ],
      ),
    );
  }
}
