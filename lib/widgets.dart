import 'package:flutter/material.dart';

import 'theme.dart';

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, required this.child,
      this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: AppColors.primary, letterSpacing: 0.4)),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class LoadError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const LoadError(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: AppColors.mutedForeground),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mutedForeground)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
            ],
          ],
        ),
      ),
    );
  }
}

/// One quote-like row; works for any idx list whose items carry
/// symbol/price/change_pct (quotes, gainers, bandar rows, ...).
class QuoteRow extends StatelessWidget {
  final Map<String, dynamic> q;
  final VoidCallback? onTap;
  final Widget? trailing;
  const QuoteRow(this.q, {super.key, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final symbol = '${q['symbol'] ?? ''}';
    final name = '${q['name'] ?? ''}';
    final price = (q['price'] as num?) ?? (q['close'] as num?);
    final pct = (q['change_pct'] as num?);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      title: Row(
        children: [
          Text(symbol,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.mutedForeground, fontSize: 12)),
          ),
        ],
      ),
      subtitle: q['signal'] != null
          ? Text('${q['signal']}${q['phase'] != null ? ' · ${q['phase']}' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.accent))
          : null,
      trailing: trailing ??
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtNum(price),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              Text(fmtPct(pct),
                  style: TextStyle(
                      color: pctColor(pct),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
    );
  }
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'Data dari sumber gratis (delayed). Analisis & edukasi — bukan nasihat investasi.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.mutedForeground, fontSize: 11),
      ),
    );
  }
}

/// Renders scalar entries of a map as label:value rows (defensive display
/// for idx payloads whose exact shape varies by endpoint).
class ScalarRows extends StatelessWidget {
  final Map<String, dynamic> map;
  final Map<String, String> labels;
  final int maxRows;
  const ScalarRows(this.map, {super.key, this.labels = const {}, this.maxRows = 14});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final e in map.entries) {
      if (rows.length ~/ 1 >= maxRows) break;
      final v = e.value;
      if (v == null || v is Map || v is List) continue;
      String text;
      if (v is num) {
        text = v is int || v == v.roundToDouble() && v.abs() >= 100
            ? fmtNum(v)
            : v.toStringAsFixed(2).replaceAll('.', ',');
        if (e.key.contains('pct')) text = fmtPct(v);
      } else if (v is bool) {
        text = v ? 'Ya' : 'Tidak';
      } else {
        text = '$v';
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(labels[e.key] ?? e.key,
                  style: const TextStyle(
                      color: AppColors.mutedForeground, fontSize: 12.5)),
            ),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ));
    }
    if (rows.isEmpty) {
      return const Text('Tidak ada data.',
          style: TextStyle(color: AppColors.mutedForeground));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
