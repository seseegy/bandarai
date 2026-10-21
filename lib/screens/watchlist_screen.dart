import 'package:flutter/material.dart';

import '../idx_runner.dart';
import '../settings.dart';
import '../widgets.dart';
import 'stock_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<String> _symbols = [];
  List<dynamic> _quotes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final w = await AppSettings.watchlist();
      if (!mounted) return;
      setState(() => _symbols = w);
      if (w.isNotEmpty) {
        try {
          final idx = await IdxRunner.instance();
          final q = await idx.run(['stocks', 'quote', w.join(',')]);
          if (mounted && q is List) setState(() => _quotes = q);
        } catch (_) {
          // Harga gagal dimuat bukan masalah besar — simbolnya tetap tampil.
        }
      } else {
        if (mounted) setState(() => _quotes = []);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      // Apa pun yang terjadi, spinner TIDAK boleh muter selamanya.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final c = TextEditingController();
    final sym = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah emiten'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Kode emiten, mis. BBCA'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(c.text),
              child: const Text('Tambah')),
        ],
      ),
    );
    final s = sym?.trim().toUpperCase() ?? '';
    if (s.isEmpty || _symbols.contains(s)) return;
    final w = [..._symbols, s];
    await AppSettings.setWatchlist(w);
    _load();
  }

  Future<void> _remove(String s) async {
    final w = _symbols.where((e) => e != s).toList();
    await AppSettings.setWatchlist(w);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bySymbol = <String, Map<String, dynamic>>{
      for (final q in _quotes)
        '${(q as Map)['symbol']}': q.cast<String, dynamic>()
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Tambah emiten',
              onPressed: _add),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 40, color: Color(0xFFEF4444)),
                        const SizedBox(height: 12),
                        const Text('Watchlist gagal dimuat.',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8), fontSize: 12.5)),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 17),
                          label: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : _symbols.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_border_rounded,
                                size: 44, color: Color(0xFFF59E0B)),
                            const SizedBox(height: 12),
                            const Text('Belum ada emiten di watchlist.',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            const Text(
                                'Ketuk tombol + di kanan atas untuk menambah emiten yang mau kamu pantau.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 12.5)),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      SectionCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Column(children: [
                          for (final s in _symbols)
                            QuoteRow(
                              bySymbol[s] ??
                                  {'symbol': s, 'name': 'memuat…'},
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => StockScreen(s))),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 18),
                                tooltip: 'Hapus $s',
                                onPressed: () => _remove(s),
                              ),
                            ),
                        ]),
                      ),
                      const Disclaimer(),
                    ],
                  ),
                ),
    );
  }
}
