import 'package:flutter/material.dart';

import '../idx_runner.dart';
import '../theme.dart';
import '../widgets.dart';

/// One OHLC candle parsed defensively from an idx history payload.
class Candle {
  final DateTime? time;
  final double open;
  final double high;
  final double low;
  final double close;
  const Candle({
    this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

Candle? _parseCandle(dynamic raw) {
  if (raw is! Map) return null;
  final o = _num(raw['open']);
  final h = _num(raw['high']);
  final l = _num(raw['low']);
  final c = _num(raw['close']);
  if (o == null || h == null || l == null || c == null) return null;
  return Candle(
    time: raw['time'] is String ? DateTime.tryParse(raw['time'] as String) : null,
    open: o,
    high: h,
    low: l,
    close: c,
  );
}

/// Candlestick chart drawn with a plain [CustomPainter] — no chart package.
/// Up candles use [AppColors.up], down [AppColors.down]; thin grid lines in
/// [AppColors.border], axis labels in [AppColors.mutedForeground].
class PriceChart extends StatelessWidget {
  final List<Candle> candles;
  final double height;
  const PriceChart({super.key, required this.candles, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _CandlePainter(candles),
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  _CandlePainter(this.candles);

  static const _rightPad = 48.0;
  static const _bottomPad = 16.0;
  static const _topPad = 6.0;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  String _fmtDate(DateTime? t) {
    if (t == null) return '';
    final yy = (t.year % 100).toString().padLeft(2, '0');
    return '${_months[t.month - 1]} $yy';
  }

  void _label(Canvas canvas, String text, Offset pos, Color color,
      {bool bold = false, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, alignRight ? Offset(pos.dx - tp.width, pos.dy) : pos);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final plotW = size.width - _rightPad;
    final plotH = size.height - _topPad - _bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    var minP = candles.first.low;
    var maxP = candles.first.high;
    for (final c in candles) {
      if (c.low < minP) minP = c.low;
      if (c.high > maxP) maxP = c.high;
    }
    var span = maxP - minP;
    if (span <= 0) {
      span = maxP.abs() * 0.02 + 1;
      minP -= span / 2;
      maxP += span / 2;
      span = maxP - minP;
    }
    final padY = span * 0.06;
    final lo = minP - padY;
    final hi = maxP + padY;
    final range = hi - lo;

    double y(double price) => _topPad + (hi - price) / range * plotH;

    // Horizontal grid lines (thin, muted).
    final grid = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 3; i++) {
      final gy = _topPad + plotH * i / 3;
      canvas.drawLine(Offset(0, gy), Offset(plotW, gy), grid);
    }

    // Right-side price axis labels: period high (top) and low (bottom).
    _label(canvas, fmtNum(maxP), Offset(plotW + 5, _topPad - 2),
        AppColors.mutedForeground);
    _label(canvas, fmtNum(minP), Offset(plotW + 5, _topPad + plotH - 8),
        AppColors.mutedForeground);

    // Candles: wick line + body rect.
    final slot = plotW / candles.length;
    final bodyW = (slot * 0.62).clamp(1.0, 14.0);
    final wick = Paint()..strokeWidth = 1;
    final body = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final cx = slot * i + slot / 2;
      final col = c.close >= c.open ? AppColors.up : AppColors.down;
      wick.color = col;
      body.color = col;
      canvas.drawLine(Offset(cx, y(c.high)), Offset(cx, y(c.low)), wick);
      final top = y(c.open > c.close ? c.open : c.close);
      final bottom = y(c.open < c.close ? c.open : c.close);
      final h = (bottom - top) < 1 ? 1.0 : bottom - top;
      canvas.drawRect(
          Rect.fromLTWH(cx - bodyW / 2, top, bodyW, h), body);
    }

    // Dashed line at the last close, coloured by the period direction.
    final last = candles.last;
    final lineColor =
        last.close >= candles.first.close ? AppColors.up : AppColors.down;
    final ly = y(last.close);
    final dashPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.7)
      ..strokeWidth = 0.8;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < plotW) {
      final end = (x + dash) > plotW ? plotW : x + dash;
      canvas.drawLine(Offset(x, ly), Offset(end, ly), dashPaint);
      x += dash + gap;
    }
    _label(canvas, fmtNum(last.close), Offset(plotW + 5, ly - 5), lineColor,
        bold: true);

    // Date labels: first candle at left, last candle at right.
    _label(canvas, _fmtDate(candles.first.time),
        Offset(0, size.height - _bottomPad + 4), AppColors.mutedForeground);
    _label(canvas, _fmtDate(last.time),
        Offset(plotW, size.height - _bottomPad + 4), AppColors.mutedForeground,
        alignRight: true);
  }

  @override
  bool shouldRepaint(_CandlePainter oldDelegate) =>
      oldDelegate.candles != candles;
}

class _PeriodOption {
  final String label;
  final String period;
  final String interval;
  const _PeriodOption(this.label, this.period, this.interval);
}

const _periods = [
  _PeriodOption('1B', '1mo', '1d'),
  _PeriodOption('3B', '3mo', '1d'),
  _PeriodOption('6B', '6mo', '1d'),
  _PeriodOption('1T', '1y', '1d'),
  _PeriodOption('5T', '5y', '1wk'), // weekly candles keep the count sane
];

/// Self-loading "GRAFIK HARGA" section for the stock page: period chips,
/// period change % + high/low stats, and the candlestick chart. Loads its own
/// data via the on-device idx binary and fails soft (inline error + retry).
class PriceChartSection extends StatefulWidget {
  final String symbol;
  const PriceChartSection({super.key, required this.symbol});

  @override
  State<PriceChartSection> createState() => _PriceChartSectionState();
}

class _PriceChartSectionState extends State<PriceChartSection> {
  int _sel = 3; // 1T default
  int _reqId = 0;
  List<Candle> _candles = const [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_reqId;
    setState(() {
      _loading = true;
      _error = false;
    });
    final p = _periods[_sel];
    try {
      final idx = await IdxRunner.instance();
      final data = await idx.run(
        [
          'stocks', 'history', widget.symbol,
          '--period', p.period,
          '--interval', p.interval,
        ],
        timeout: const Duration(seconds: 150),
      );
      if (!mounted || req != _reqId) return;
      final map = (data as Map).cast<String, dynamic>();
      final raw = (map['candles'] as List?) ?? const [];
      final parsed = <Candle>[];
      for (final r in raw) {
        final c = _parseCandle(r);
        if (c != null) parsed.add(c);
      }
      setState(() {
        _candles = parsed;
        _summary = (map['summary'] as Map?)?.cast<String, dynamic>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || req != _reqId) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _select(int i) {
    if (i == _sel) return;
    setState(() => _sel = i);
    _load();
  }

  double? get _changePct {
    final s = _num(_summary?['change_pct']);
    if (s != null) return s;
    if (_candles.length >= 2 && _candles.first.close != 0) {
      return (_candles.last.close - _candles.first.close) /
          _candles.first.close *
          100;
    }
    return null;
  }

  double? get _periodHigh {
    final s = _num(_summary?['high']);
    if (s != null) return s;
    if (_candles.isEmpty) return null;
    return _candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
  }

  double? get _periodLow {
    final s = _num(_summary?['low']);
    if (s != null) return s;
    if (_candles.isEmpty) return null;
    return _candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Grafik gagal dimuat',
                style: TextStyle(
                    color: AppColors.mutedForeground, fontSize: 12.5)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    if (_candles.isEmpty) {
      return const Center(
        child: Text('Tidak ada data grafik untuk periode ini.',
            style:
                TextStyle(color: AppColors.mutedForeground, fontSize: 12.5)),
      );
    }
    return PriceChart(candles: _candles, height: 200);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _changePct;
    final showStats = !_loading && !_error && _candles.isNotEmpty;
    return SectionCard(
      title: 'GRAFIK HARGA',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showStats) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtPct(pct),
                    style: TextStyle(
                        color: pctColor(pct),
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_periods[_sel].label,
                      style: const TextStyle(
                          color: AppColors.mutedForeground, fontSize: 11.5)),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Tertinggi ${fmtNum(_periodHigh)}',
                        style: const TextStyle(fontSize: 11.5)),
                    Text('Terendah ${fmtNum(_periodLow)}',
                        style: const TextStyle(
                            color: AppColors.mutedForeground, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(height: 200, child: _content()),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _periods.length; i++)
                ChoiceChip(
                  label: Text(_periods[i].label),
                  selected: i == _sel,
                  onSelected: (_) => _select(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
