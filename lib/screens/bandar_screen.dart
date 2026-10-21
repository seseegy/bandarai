import 'package:flutter/material.dart';

import '../idx_runner.dart';
import '../theme.dart';
import '../widgets.dart';
import 'stock_screen.dart';

class BandarScreen extends StatefulWidget {
  const BandarScreen({super.key});

  @override
  State<BandarScreen> createState() => _BandarScreenState();
}

class _BandarScreenState extends State<BandarScreen> {
  static const _presets = {
    'quiet-accumulation': 'Akumulasi Diam-diam',
    'big-accumulation': 'Akumulasi Besar',
    'accumulation': 'Akumulasi',
    'foreign-accumulation': 'Akumulasi Asing',
    'below-bandar': 'Di Bawah Bandar',
    'distribution': 'Distribusi',
    'big-distribution': 'Distribusi Besar',
    'quiet-distribution': 'Distribusi Diam-diam',
  };
  String _preset = 'quiet-accumulation';
  List<dynamic> _rows = [];
  bool _loading = false;
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
    try {
      final idx = await IdxRunner.instance();
      final r = await idx.run(['bandar', 'screen', '--preset', _preset],
          timeout: const Duration(seconds: 300));
      if (!mounted) return;
      setState(() {
        _rows = r is List
            ? r
            : (r is Map ? (r['rows'] as List? ?? r['results'] as List? ?? []) : []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar Bandar',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: [
                for (final e in _presets.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _preset == e.key,
                      onSelected: (_) {
                        setState(() => _preset = e.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Dihitung dari ringkasan broker IPOT atas 100 saham teraktif. Scan bisa memakan waktu — data di-cache idx selama sesi berjalan.',
                  style: TextStyle(
                      color: AppColors.mutedForeground, fontSize: 11.5)),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(_error!, onRetry: _load)
                    : _rows.isEmpty
                        ? const Center(
                            child: Text('Tidak ada saham yang cocok.',
                                style: TextStyle(
                                    color: AppColors.mutedForeground)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.all(14),
                              children: [
                                SectionCard(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  child: Column(children: [
                                    for (final r in _rows)
                                      QuoteRow(
                                        (r as Map).cast<String, dynamic>(),
                                        onTap: () => Navigator.of(context)
                                            .push(MaterialPageRoute(
                                                builder: (_) => StockScreen(
                                                    '${r['symbol']}'))),
                                      ),
                                  ]),
                                ),
                                const Disclaimer(),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
