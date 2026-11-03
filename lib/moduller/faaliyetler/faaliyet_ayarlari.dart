import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../veri/faaliyet_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'faaliyet_ortak.dart';

/// Faaliyet kategorileri ve yerleri (web "Faaliyetler ▸ Ayarlar"): ekle, yeniden adlandır, sil.
/// Bu işlemler anlık olarak sunucuda yapılır, bağlantı gerekir.
class FaaliyetAyarlari extends StatefulWidget {
  const FaaliyetAyarlari({super.key, required this.veri});

  final VeriKatmani veri;

  @override
  State<FaaliyetAyarlari> createState() => _FaaliyetAyarlariState();
}

class _FaaliyetAyarlariState extends State<FaaliyetAyarlari> {
  FaaliyetReferans _ref = FaaliyetReferans({});
  bool _yuklendi = false;
  bool _mesgul = false;

  FaaliyetDeposu get _depo => widget.veri.faaliyetler;

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
    if (!mounted) return;
    setState(() {
      _ref = FaaliyetReferans(r);
      _yuklendi = true;
    });
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _calistir(Future<void> Function() is_) async {
    final senk = widget.veri.motor.faaliyetSenkron;
    if (senk == null || _mesgul) return;
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

  Future<void> _adSor(String tur, {int? no, String? ad}) async {
    final denetci = TextEditingController(text: ad ?? '');
    final yeni = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          '${tur == 'kategori' ? 'Kategori' : 'Yer'} ${no == null ? 'ekle' : 'adı'}',
        ),
        content: TextField(
          controller: denetci,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tur == 'kategori' ? 'Kategori adı' : 'Yer adı',
          ),
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
    await _calistir(
      () => widget.veri.motor.faaliyetSenkron!.ayarKaydet(tur, temiz, no: no),
    );
  }

  Future<void> _sil(String tur, int no, String ad) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('“$ad” silinsin mi?'),
        content: const Text(
          'Kayıt çöp kutusuna taşınır. Kullanımda olan kategori ya da yer silinemez.',
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
    if (onay != true) return;
    await _calistir(() => widget.veri.motor.faaliyetSenkron!.ayarSil(tur, no));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(
      zemin,
      tema.colorScheme.primary,
      acik ? 0.10 : 0.14,
    )!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            ModulHero(
              geri: true,
              ikon: Icons.tune_rounded,
              baslik: 'KATEGORİ VE YERLER',
              altBaslik: 'Faaliyet ayarları',
              alt: Container(
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  labelColor: const Color(0xFF002666),
                  unselectedLabelColor: Colors.white,
                  labelStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: 'Kategoriler'),
                    Tab(text: 'Yerler'),
                  ],
                ),
              ),
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
                    : TabBarView(
                        children: [
                          _Liste(
                            tur: 'kategori',
                            liste: _ref.kategoriler,
                            mesgul: _mesgul,
                            ekle: () => _adSor('kategori'),
                            duzenle: (no, ad) =>
                                _adSor('kategori', no: no, ad: ad),
                            sil: (no, ad) => _sil('kategori', no, ad),
                          ),
                          _Liste(
                            tur: 'yer',
                            liste: _ref.yerler,
                            mesgul: _mesgul,
                            ekle: () => _adSor('yer'),
                            duzenle: (no, ad) => _adSor('yer', no: no, ad: ad),
                            sil: (no, ad) => _sil('yer', no, ad),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({
    required this.tur,
    required this.liste,
    required this.mesgul,
    required this.ekle,
    required this.duzenle,
    required this.sil,
  });

  final String tur;
  final List<Map<String, dynamic>> liste;
  final bool mesgul;
  final VoidCallback ekle;
  final void Function(int no, String ad) duzenle;
  final void Function(int no, String ad) sil;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProgramKutu(
                  baslik: tur == 'kategori' ? 'Kategoriler' : 'Yerler',
                  ikon: tur == 'kategori'
                      ? Icons.category_outlined
                      : Icons.place_outlined,
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
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Henüz kayıt yok.',
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      for (final x in liste)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: tur == 'kategori'
                              ? Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: kategoriRengi(
                                      x['no'] as int,
                                      koyu: tema.brightness == Brightness.dark,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : Icon(
                                  Icons.place_outlined,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                          title: Text('${x['adi']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Yeniden adlandır',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: mesgul
                                    ? null
                                    : () => duzenle(
                                        x['no'] as int,
                                        '${x['adi']}',
                                      ),
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: cs.error,
                                ),
                                onPressed: mesgul
                                    ? null
                                    : () => sil(x['no'] as int, '${x['adi']}'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: mesgul ? null : ekle,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            tur == 'kategori' ? 'Kategori ekle' : 'Yer ekle',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
