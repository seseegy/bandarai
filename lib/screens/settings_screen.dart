import 'package:flutter/material.dart';

import '../ai.dart';
import '../idx_runner.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _grip = TextEditingController();
  final _s1 = TextEditingController();
  List<String> _models = [];
  String? _model;
  String? _idxInfo;
  bool _busy = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _grip.text = await AppSettings.griphubKey() ?? '';
    _s1.text = await AppSettings.s1Key() ?? '';
    _model = await AppSettings.model();
    if (mounted) setState(() {});
    try {
      final idx = await IdxRunner.instance();
      final v = idx.binaryExists
          ? await idx.version()
          : 'binary idx TIDAK ditemukan di APK';
      if (mounted) setState(() => _idxInfo = v);
    } catch (e) {
      if (mounted) setState(() => _idxInfo = 'idx error: $e');
    }
  }

  @override
  void dispose() {
    _grip.dispose();
    _s1.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await AppSettings.setGriphubKey(_grip.text);
      await AppSettings.setS1Key(_s1.text);
      await AppSettings.setModel(_model);
      // Baca balik: pastikan key benar-benar tersimpan di HP ini,
      // supaya user tidak menebak-nebak seperti sebelumnya.
      final readBack = await AppSettings.griphubKey();
      final expect = _grip.text.trim();
      final ok = expect.isEmpty
          ? (readBack == null || readBack.isEmpty)
          : readBack == expect;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Gagal menyimpan: key tidak terbaca kembali. Coba lagi ya.'),
          duration: Duration(seconds: 5),
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
          SizedBox(width: 8),
          Text('Tersimpan — pengaturan sudah aktif.'),
        ]),
        duration: Duration(seconds: 3),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadModels() async {
    final key = _grip.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Isi dulu API key GripHub-nya.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final models = await AiAnalyst.listModels(key);
      if (mounted) {
        setState(() {
          _models = models;
          _model ??= models.isNotEmpty ? models.first : null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${models.length} model ditemukan.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'GRIPHUB ROUTER (AI)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Key kamu sendiri — dipakai langsung dari HP ini ke griphubrouter.web.id, tidak lewat server mana pun.',
                    style: TextStyle(
                        color: AppColors.mutedForeground, fontSize: 12.5)),
                const SizedBox(height: 10),
                TextField(
                  controller: _grip,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'API key GripHub',
                      hintText: 'sk-…'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _loadModels,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Muat daftar model'),
                    ),
                    const SizedBox(width: 10),
                    if (_busy)
                      const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                if (_models.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _model,
                    decoration: const InputDecoration(labelText: 'Model AI'),
                    items: [
                      for (final m in _models)
                        DropdownMenuItem(value: m, child: Text(m))
                    ],
                    onChanged: (v) => setState(() => _model = v),
                  ),
                ],
              ],
            ),
          ),
          SectionCard(
            title: 'SEARCH1API (BERITA WEB, OPSIONAL)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Tanpa key ini, analis tetap bekerja dari data idx. Dengan key, analis bisa mencari penyebab pergerakan dari seluruh web.',
                    style: TextStyle(
                        color: AppColors.mutedForeground, fontSize: 12.5)),
                const SizedBox(height: 10),
                TextField(
                  controller: _s1,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'API key Search1API',
                      hintText: 'Opsional'),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'MESIN DATA (ON-DEVICE)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_idxInfo ?? 'memeriksa binary idx…',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                const Text(
                    'Binary idx berjalan lokal di HP ini. Cache, config, dan database kepemilikan KSEI tersimpan di penyimpanan aplikasi.',
                    style: TextStyle(
                        color: AppColors.mutedForeground, fontSize: 12.5)),
              ],
            ),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Simpan'),
          ),
          const SizedBox(height: 8),
          const Disclaimer(),
        ],
      ),
    );
  }
}
