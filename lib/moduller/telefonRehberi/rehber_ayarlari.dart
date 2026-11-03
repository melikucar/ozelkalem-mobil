import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../veri/rehber.dart';
import '../../veri/rehber_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'rehber_ortak.dart';

/// Rehber kategorileri (web "Telefonlar ▸ Ayarlar"): ekle, yeniden adlandır, sil.
/// Bu işlemler anlık olarak sunucuda yapılır, bağlantı gerekir. Kişi bulunan kategori silinemez.
class RehberAyarlari extends StatefulWidget {
  const RehberAyarlari({super.key, required this.veri});

  final VeriKatmani veri;

  @override
  State<RehberAyarlari> createState() => _RehberAyarlariState();
}

class _RehberAyarlariState extends State<RehberAyarlari> {
  RehberReferans _ref = RehberReferans({});
  Map<int, int> _sayilar = {};
  bool _yuklendi = false;
  bool _mesgul = false;

  RehberDeposu get _depo => widget.veri.rehber;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yukle);
    _yukle();
  }

  @override
  void dispose() {
    _depo.removeListener(_yukle);
    super.dispose();
  }

  Future<void> _yukle() async {
    final r = await _depo.referans();
    final s = await _depo.kategoriSayilari(const KisiFiltre());
    if (!mounted) return;
    setState(() {
      _ref = RehberReferans(r);
      _sayilar = s;
      _yuklendi = true;
    });
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _calistir(Future<void> Function() is_) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await is_();
    } on ApiHata catch (e) {
      _mesaj(
        e.agHatasi ? 'Bu işlem için internet bağlantısı gerekir.' : e.mesaj,
      );
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _adSor({int? no, String? ad}) async {
    final denetci = TextEditingController(text: ad ?? '');
    final yeni = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(no == null ? 'Kategori ekle' : 'Kategori adı'),
        content: TextField(
          controller: denetci,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Kategori adı'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, denetci.text),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    denetci.dispose();
    final temiz = yeni?.trim() ?? '';
    if (temiz.isEmpty || temiz == ad) return;
    final senk = widget.veri.motor.rehberSenkron;
    if (senk == null) return;
    await _calistir(() => senk.kategoriKaydet(temiz, no: no));
  }

  Future<void> _sil(int no, String ad) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('“$ad” silinsin mi?'),
        content: const Text(
          'Kategori çöp kutusuna taşınır. İçinde kişi bulunan kategori silinemez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    final senk = widget.veri.motor.rehberSenkron;
    if (onay != true || senk == null) return;
    await _calistir(() => senk.kategoriSil(no));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final liste = _ref.kategoriler;
    return Scaffold(
      body: Column(
        children: [
          const ModulHero(
            geri: true,
            ikon: Icons.category_outlined,
            baslik: 'KATEGORİLER',
            altBaslik: 'Rehber ayarları',
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.25, 1],
                ),
              ),
              child: !_yuklendi
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: ProgramKutu(
                              baslik: 'Rehber kategorileri',
                              ikon: Icons.category_outlined,
                              sag: Text(
                                '${liste.length}',
                                style: tema.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              cocuk: Column(
                                children: [
                                  if (liste.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Henüz kategori yok. Kişi eklemek için en az bir kategori gerekir.',
                                        style: tema.textTheme.bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  for (final x in liste)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: rehberKategoriRengi(
                                            x['no'] as int,
                                            koyu: !acik,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      title: Text('${x['adi']}'),
                                      subtitle: Text(
                                        '${_sayilar[x['no']] ?? 0} kişi',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Yeniden adlandır',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 20,
                                            ),
                                            onPressed: _mesgul
                                                ? null
                                                : () => _adSor(
                                                    no: x['no'] as int,
                                                    ad: '${x['adi']}',
                                                  ),
                                          ),
                                          IconButton(
                                            tooltip: 'Sil',
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: cs.error,
                                            ),
                                            onPressed: _mesgul
                                                ? null
                                                : () => _sil(
                                                    x['no'] as int,
                                                    '${x['adi']}',
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.tonalIcon(
                                      onPressed: _mesgul
                                          ? null
                                          : () => _adSor(),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Kategori ekle'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
}
