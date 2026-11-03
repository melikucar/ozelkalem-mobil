import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_istemci.dart';
import '../../diger/cekince_esitle.dart';
import '../../diger/modul_hero.dart';
import '../../veri/bakanlik.dart';
import '../../veri/veri_katmani.dart';
import '../../veri/yazi_formatlari.dart';
import '../programlar/program_ortak.dart';
import 'bakanlik_oneri.dart';

/// Bakanlık Teşkilatları: web modülünün mobil karşılığı. Bakanlık sekmeleri, grup başlıklı (Bakan, Bakan Yardımcıları, Genel
/// Müdürlükler…) kurum kartları, arama, dokununca arama/e-posta. Liste ortaktır (değiştirilemez); makam değişiklik/ekleme/kaldırma ÖNERİR.
/// Liste cihazda saklanır (çevrimdışı okunur); öneriler bağlantı gerektirir.
class BakanlikSayfasi extends StatefulWidget {
  const BakanlikSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<BakanlikSayfasi> createState() => _BakanlikSayfasiState();
}

class _BakanlikSayfasiState extends State<BakanlikSayfasi> {
  late final BakanlikServisi _s = BakanlikServisi(
    widget.veri.motor.api,
    widget.veri.yerel,
  );

  int _bakanlik = 0; // 0: hepsi
  bool _yuklendi = false;
  bool _cevrimdisi = false;
  bool _aramaAcik = false;
  final _arama = TextEditingController();
  String _kelime = '';
  Timer? _bekle;
  bool _eskiCalisiyor = false;
  bool _surukleniyor = false;

  @override
  void initState() {
    super.initState();
    widget.veri.motor.addListener(_motorDegisti);
    _baslat();
  }

  @override
  void dispose() {
    widget.veri.motor.removeListener(_motorDegisti);
    _bekle?.cancel();
    _arama.dispose();
    super.dispose();
  }

  /// Eşitleme (aşağı çekme dahil) bitince liste de sunucudan yenilenir.
  void _motorDegisti() {
    final c = widget.veri.motor.calisiyor;
    final bitti = _eskiCalisiyor && !c;
    _eskiCalisiyor = c;
    if (bitti) _yenile();
  }

  Future<void> _baslat() async {
    final var_ = await _s.onbellektenYukle();
    if (mounted && var_) setState(() => _yuklendi = true);
    await _yenile();
  }

  Future<void> _yenile() async {
    try {
      await _s.yenile();
      _cevrimdisi = false;
    } on ApiHata catch (e) {
      _cevrimdisi = true;
      if (!e.agHatasi && mounted) _mesaj(e.mesaj);
    }
    if (mounted) setState(() => _yuklendi = true);
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  void _araDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _kelime = v);
    });
  }

  List<Kurum> get _suzulmus {
    final k = aramaMetni(_kelime);
    return [
      for (final x in _s.kurumlar)
        if ((_bakanlik == 0 || x.katno == _bakanlik) &&
            (k.isEmpty || x.ara.contains(k)))
          x,
    ];
  }

  String _bakanlikAdi(int no) {
    for (final b in _s.bakanliklar) {
      if (b.no == no) return b.adi;
    }
    return '';
  }

  Future<void> _ara(String tel) async {
    final temiz = tel.replaceAll(RegExp(r'[^0-9+]'), '');
    if (temiz.isEmpty) return;
    await launchUrl(Uri.parse('tel:$temiz')).catchError((_) => false);
  }

  Future<void> _eposta(String ad) async {
    await launchUrl(Uri.parse('mailto:$ad')).catchError((_) => false);
  }

  Future<void> _oneriAc({required String tip, Kurum? kurum, int? katNo}) async {
    final sonuc = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BakanlikOneriFormu(
          servis: _s,
          tip: tip,
          kurum: kurum,
          katNo: katNo ?? kurum?.katno ?? _bakanlik,
          bakanlikAdi: _bakanlikAdi(katNo ?? kurum?.katno ?? _bakanlik),
          bakanliklar: _s.bakanliklar,
        ),
      ),
    );
    if (sonuc != null && mounted) {
      setState(() {});
      _mesaj(sonuc);
    }
  }

  void _ayrinti(Kurum k) {
    final bek = _s.bekleyen[k.no];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        final tema = Theme.of(c);
        final cs = tema.colorScheme;
        Widget satir(
          IconData ikon,
          String etiket,
          String deger, {
          VoidCallback? tikla,
        }) => deger.isEmpty
            ? const SizedBox.shrink()
            : ListTile(
                dense: true,
                leading: Icon(ikon, color: cs.primary),
                title: Text(
                  deger,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(etiket),
                onTap: tikla,
                trailing: tikla == null
                    ? null
                    : Icon(Icons.chevron_right_rounded, color: cs.outline),
              );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.baslik,
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (k.altBaslik.isNotEmpty)
                        Text(
                          k.altBaslik,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _bakanlikAdi(k.katno),
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                satir(
                  Icons.call_outlined,
                  k.dahili.isEmpty ? 'Telefon' : 'Telefon · Dahili ${k.dahili}',
                  k.telefon,
                  tikla: k.telefon.isEmpty ? null : () => _ara(k.telefon),
                ),
                satir(
                  Icons.call_outlined,
                  k.dahili2.isEmpty
                      ? 'Telefon 2'
                      : 'Telefon 2 · Dahili ${k.dahili2}',
                  k.telefon2,
                  tikla: k.telefon2.isEmpty ? null : () => _ara(k.telefon2),
                ),
                satir(Icons.fax_outlined, 'Faks', k.faks),
                satir(
                  Icons.alternate_email_rounded,
                  'E-posta',
                  k.eposta,
                  tikla: k.eposta.isEmpty ? null : () => _eposta(k.eposta),
                ),
                const Divider(height: 24),
                if (bek != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(c);
                        try {
                          final m = await _s.iptal((bek['no'] as num).toInt());
                          if (mounted) {
                            setState(() {});
                            _mesaj(m);
                          }
                        } on ApiHata catch (e) {
                          if (mounted) {
                            _mesaj(
                              e.agHatasi
                                  ? 'İptal için internet bağlantısı gerekir.'
                                  : e.mesaj,
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.undo_rounded),
                      label: Text(
                        'Bekleyen ${oneriTipAdi('${bek['tip']}').toLowerCase()} önerinizi iptal edin',
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(c);
                              _oneriAc(tip: 'degistir', kurum: k);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Değişiklik öner'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(c);
                              _oneriAc(tip: 'kaldir', kurum: k);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.error,
                            ),
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Kaldırılsın'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onerilerim() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => BakanlikOnerilerim(servis: _s)));

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
    final motor = widget.veri.motor;
    final liste = _suzulmus;
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: !widget.sekme,
            ikon: Icons.corporate_fare_outlined,
            baslik: 'Bakanlık Teşkilatları',
            altBaslik: _yuklendi
                ? '${liste.length} kurum${_cevrimdisi ? ' · çevrimdışı' : ''}${_s.bekleyen.isNotEmpty ? ' · ${_s.bekleyen.length} öneri bekliyor' : ''}'
                : 'Yükleniyor…',
            eylemler: [
              IconButton(
                tooltip: _aramaAcik ? 'Aramayı kapat' : 'Ara',
                icon: Icon(
                  _aramaAcik ? Icons.close_rounded : Icons.search_rounded,
                ),
                onPressed: () {
                  setState(() => _aramaAcik = !_aramaAcik);
                  if (!_aramaAcik && _arama.text.isNotEmpty) {
                    _arama.clear();
                    setState(() => _kelime = '');
                  }
                },
              ),
              PopupMenuButton<String>(
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'oneriler') _onerilerim();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'oneriler',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.lightbulb_outline),
                      title: Text('Önerilerim'),
                    ),
                  ),
                ],
              ),
            ],
            alt: (_aramaAcik || _arama.text.isNotEmpty)
                ? HeroArama(
                    controller: _arama,
                    ipucu: 'Kurum, ünvan, telefon ya da e-postada ara',
                    degisti: _araDegisti,
                  )
                : null,
          ),
          _secimSeridi(tema),
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
              child: Row(
                children: [
                  Expanded(
                    child: CekinceEsitle(
                      motor: motor,
                      child: _govde(tema, liste),
                    ),
                  ),
                  _BakanlikCubugu(
                    bakanliklar: _s.bakanliklar,
                    sayilar: _sayilar,
                    secili: _bakanlik,
                    surukleniyor: _surukleniyor,
                    sec: (no) => setState(() => _bakanlik = no),
                    baslat: () => setState(() => _surukleniyor = true),
                    bitir: () => setState(() => _surukleniyor = false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<int, int> get _sayilar {
    final m = <int, int>{};
    for (final k in _s.kurumlar) {
      m[k.katno] = (m[k.katno] ?? 0) + 1;
    }
    return m;
  }

  /// Seçili bakanlığı gösteren ince şerit (kaldırmak için dokunulur); seçim yokken görünmez.
  Widget _secimSeridi(ThemeData tema) {
    if (_bakanlik == 0) return const SizedBox.shrink();
    final cs = tema.colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.account_balance_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _bakanlikAdi(_bakanlik),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _bakanlik = 0),
            child: const Text('Tümünü göster'),
          ),
        ],
      ),
    );
  }

  Widget _govde(ThemeData tema, List<Kurum> liste) {
    final cs = tema.colorScheme;
    if (!_yuklendi) return const Center(child: CircularProgressIndicator());
    if (_s.kurumlar.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.cloud_off_rounded, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            'Liste henüz indirilmedi',
            textAlign: TextAlign.center,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'İnternet bağlantısı olunca bu sayfayı aşağı çekerek yenileyin.',
            textAlign: TextAlign.center,
            style: tema.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    if (liste.isEmpty && _kelime.trim().isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.search_off_rounded, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            'Kriterlere uygun kurum yok',
            textAlign: TextAlign.center,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    // bakanlık > grup sırasıyla başlıklı liste
    final ogeler = <Object>[];
    final bakanlikSirasi = _bakanlik == 0
        ? _s.bakanliklar.map((b) => b.no).toList()
        : [_bakanlik];
    for (final bn in bakanlikSirasi) {
      final bk = liste.where((k) => k.katno == bn).toList();
      final aramada = _kelime.trim().isNotEmpty;
      if (bk.isEmpty && aramada) continue;
      if (_bakanlik == 0) ogeler.add(_bakanlikAdi(bn));
      final gruplar = <String, List<Kurum>>{};
      for (final k in bk) {
        gruplar.putIfAbsent(k.grup, () => []).add(k);
      }
      for (final g in gruplar.keys.toList()..sort()) {
        ogeler.add(gruplar[g]!.first.grupAdi);
        ogeler.addAll(gruplar[g]!);
      }
      if (!aramada) ogeler.add(_OnerSatiri(bn));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
          itemCount: ogeler.length,
          itemBuilder: (c, i) {
            final o = ogeler[i];
            if (o is String) {
              final bakanlikBasligi =
                  _bakanlik == 0 && _s.bakanliklar.any((b) => b.adi == o);
              return Padding(
                padding: EdgeInsets.fromLTRB(4, bakanlikBasligi ? 16 : 8, 0, 8),
                child: Text(
                  bakanlikBasligi ? o.toUpperCase() : o,
                  style: (bakanlikBasligi
                      ? tema.textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        )
                      : tema.textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        )),
                ),
              );
            }
            if (o is _OnerSatiri) {
              return Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: OutlinedButton.icon(
                  onPressed: () => _oneriAc(tip: 'ekle', katNo: o.bakanlik),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text('${_bakanlikAdi(o.bakanlik)} için kurum öner'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              );
            }
            final k = o as Kurum;
            final bek = _s.bekleyen[k.no];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _KurumKarti(
                kurum: k,
                bekleyen: bek == null ? null : oneriTipAdi('${bek['tip']}'),
                tikla: () => _ayrinti(k),
                ara: k.telefon.isEmpty ? null : () => _ara(k.telefon),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Bakanlığın liste sonundaki "kurum öner" satırı.
class _OnerSatiri {
  const _OnerSatiri(this.bakanlik);

  final int bakanlik;
}

class _KurumKarti extends StatelessWidget {
  const _KurumKarti({
    required this.kurum,
    required this.tikla,
    this.ara,
    this.bekleyen,
  });

  final Kurum kurum;
  final VoidCallback tikla;
  final VoidCallback? ara;
  final String? bekleyen;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final k = kurum;
    final tel = [if (k.telefon.isNotEmpty) k.telefon].join();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: programGolgesi(context),
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tikla,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.baslik,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      if (k.altBaslik.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            k.altBaslik,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (tel.isNotEmpty ||
                          k.eposta.isNotEmpty ||
                          bekleyen != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            children: [
                              if (tel.isNotEmpty)
                                Text(
                                  k.dahili.isEmpty ? tel : '$tel · ${k.dahili}',
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (k.eposta.isNotEmpty)
                                Text(
                                  k.eposta,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              if (bekleyen != null)
                                Text(
                                  '$bekleyen önerisi bekliyor',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (ara != null)
                  IconButton(
                    tooltip: 'Ara',
                    icon: Icon(Icons.call_rounded, color: cs.primary),
                    onPressed: ara,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bakanlığın kısa adı: ilk harfi + B (Adalet Bakanlığı → AB).
String bakanlikKisaAdi(String ad) {
  final t = ad.trim();
  if (t.isEmpty) return 'B';
  final ilk = t.substring(0, 1).replaceAll('i', 'İ').replaceAll('ı', 'I');
  return '${ilk.toUpperCase()}B';
}

/// Sağ kenarda bakanlık çubuğu (rehberdeki harf çubuğu gibi): dokunup sürüklenerek bakanlık seçilir, yanında seçilen bakanlığın
/// adını ve kurum sayısını gösteren bir balon belirir. En üstteki "TÜM" tüm bakanlıkları gösterir.
class _BakanlikCubugu extends StatelessWidget {
  const _BakanlikCubugu({
    required this.bakanliklar,
    required this.sayilar,
    required this.secili,
    required this.surukleniyor,
    required this.sec,
    required this.baslat,
    required this.bitir,
  });

  final List<Bakanlik> bakanliklar;
  final Map<int, int> sayilar;
  final int secili; // 0: tümü
  final bool surukleniyor;
  final ValueChanged<int> sec;
  final VoidCallback baslat;
  final VoidCallback bitir;

  static const _adim = 27.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = bakanliklar.length + 1;
    const ust = 10.0;
    return SizedBox(
      width: 36,
      child: LayoutBuilder(
        builder: (context, k) {
          final h = k.maxHeight;
          int sira(double dy) => ((dy - ust) / _adim).floor().clamp(0, n - 1);
          int noyaCevir(int i) => i == 0 ? 0 : bakanliklar[i - 1].no;
          final aktif = secili == 0
              ? 0
              : bakanliklar.indexWhere((b) => b.no == secili) + 1;
          void git(double dy) => sec(noyaCevir(sira(dy)));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              baslat();
              git(d.localPosition.dy);
            },
            onTapUp: (_) => bitir(),
            onTapCancel: bitir,
            onVerticalDragStart: (d) {
              baslat();
              git(d.localPosition.dy);
            },
            onVerticalDragUpdate: (d) => git(d.localPosition.dy),
            onVerticalDragEnd: (_) => bitir(),
            onVerticalDragCancel: bitir,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < n; i++)
                  Positioned(
                    top: ust + i * _adim,
                    height: _adim,
                    right: 3,
                    width: 30,
                    child: _CubukOgesi(
                      etiket: i == 0
                          ? 'TÜM'
                          : bakanlikKisaAdi(bakanliklar[i - 1].adi),
                      secili: i == aktif,
                      uzaklik: !surukleniyor ? 99 : (i - aktif).abs(),
                      cs: cs,
                    ),
                  ),
                if (surukleniyor && aktif >= 0)
                  Positioned(
                    right: 46,
                    top: (ust + aktif * _adim + _adim / 2 - 28).clamp(
                      0.0,
                      h - 56,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 120,
                        maxWidth: 230,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomRight: Radius.circular(6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aktif == 0
                                ? 'Tüm bakanlıklar'
                                : bakanliklar[aktif - 1].adi,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            aktif == 0
                                ? '${sayilar.values.fold<int>(0, (a, b) => a + b)} kurum'
                                : '${sayilar[bakanliklar[aktif - 1].no] ?? 0} kurum',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onPrimary.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Çubuktaki tek kısaltma: parmağa yakın olanlar büyür ve sola doğru dalga gibi kayar (rehberdeki harf çubuğu gibi).
class _CubukOgesi extends StatelessWidget {
  const _CubukOgesi({
    required this.etiket,
    required this.secili,
    required this.uzaklik,
    required this.cs,
  });

  final String etiket;
  final bool secili;
  final int uzaklik;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final etki = uzaklik >= 4 ? 0.0 : (1 - uzaklik / 4);
    final dalga = etki * etki * (3 - 2 * etki);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      transformAlignment: Alignment.centerRight,
      transform: Matrix4.identity()
        ..translateByDouble(-34 * dalga, 0, 0, 1)
        ..scaleByDouble(1 + 0.9 * dalga, 1 + 0.9 * dalga, 1, 1),
      alignment: Alignment.center,
      child: Container(
        width: 28,
        height: 24,
        alignment: Alignment.center,
        decoration: secili
            ? BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(9),
              )
            : null,
        child: Text(
          etiket,
          style: TextStyle(
            fontSize: etiket.length > 2 ? 9 : 11,
            height: 1.1,
            fontWeight: secili ? FontWeight.w800 : FontWeight.w700,
            color: secili ? cs.onPrimary : cs.primary.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
