import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../veri/faaliyet.dart';
import '../../veri/faaliyet_deposu.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'faaliyet_ortak.dart';
import 'gorsel_gezgin.dart';

/// Kitapçıklar (yalnızca görüntüleme): web'de oluşturulmuş kitapçıkların listesi ve sayfa sayfa okuyucusu.
class KitapciklarSayfasi extends StatefulWidget {
  const KitapciklarSayfasi({super.key, required this.veri});

  final VeriKatmani veri;

  @override
  State<KitapciklarSayfasi> createState() => _KitapciklarSayfasiState();
}

class _KitapciklarSayfasiState extends State<KitapciklarSayfasi> {
  List<Kitapcik> _liste = [];
  bool _yuklendi = false;
  bool _yenileniyor = false;
  String? _hata;

  FaaliyetDeposu get _depo => widget.veri.faaliyetler;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yukle);
    _yukle();
    _tazele();
  }

  @override
  void dispose() {
    _depo.removeListener(_yukle);
    super.dispose();
  }

  Future<void> _yukle() async {
    final l = await _depo.kitapciklar();
    if (!mounted) return;
    setState(() {
      _liste = l;
      _yuklendi = true;
    });
  }

  /// Açılışta listeyi sunucudan tazeler (bağlantı yoksa saklı liste gösterilir).
  Future<void> _tazele() async {
    setState(() {
      _yenileniyor = true;
      _hata = null;
    });
    try {
      final v = await widget.veri.motor.api.get('faaliyetler/kitapciklar');
      await _depo.kitapciklarYaz(v['kitapciklar'] as List);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _hata = e.agHatasi
              ? 'Bağlantı yok; son indirilen liste gösteriliyor.'
              : e.mesaj;
        });
      }
    } finally {
      if (mounted) setState(() => _yenileniyor = false);
    }
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
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.auto_stories_outlined,
            baslik: 'KİTAPÇIKLAR',
            altBaslik: _yuklendi ? '${_liste.length} kitapçık' : null,
            eylemler: [
              if (_yenileniyor)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Yenile',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _tazele,
                ),
            ],
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
                  : _liste.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
                          child: Column(
                            children: [
                              Icon(
                                Icons.auto_stories_outlined,
                                size: 48,
                                color: tema.colorScheme.primary,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Henüz kitapçık yok',
                                style: tema.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _hata ?? 'Kitapçıklar web panelinden oluşturulur; burada yalnızca görüntülenir.',
                                textAlign: TextAlign.center,
                                style: tema.textTheme.bodySmall?.copyWith(
                                  color: tema.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                          itemCount: _liste.length + (_hata != null ? 1 : 0),
                          itemBuilder: (c, i) {
                            if (_hata != null && i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  _hata!,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: tema.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            final k = _liste[i - (_hata != null ? 1 : 0)];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _KitapKarti(
                                kitap: k,
                                tikla: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => KitapcikOkuyucu(
                                      veri: widget.veri,
                                      kitap: k,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitapKarti extends StatelessWidget {
  const _KitapKarti({required this.kitap, required this.tikla});

  final Kitapcik kitap;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final yazi = Color(renkDegeri(kitap.yazi));
    final cizgi = Color(renkDegeri(kitap.cizgi));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: programGolgesi(context),
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tikla,
          child: Row(
            children: [
              // kapak şeridi: şablon renkleri
              Container(
                width: 78,
                height: 108,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [yazi, cizgi],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.auto_stories_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kitap.baslikSatirlari.isEmpty
                            ? 'Kitapçık #${kitap.no}'
                            : kitap.baslikSatirlari.join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Bilgi(
                            Icons.event_outlined,
                            '${kitap.tarih.day} ${trAylarKisa[kitap.tarih.month]} ${kitap.tarih.year}',
                          ),
                          _Bilgi(
                            Icons.article_outlined,
                            '${kitap.faaliyetler.length} faaliyet',
                          ),
                          if (kitap.taslak)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Taslak',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (kitap.sablon.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          kitap.sablon,
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bilgi extends StatelessWidget {
  const _Bilgi(this.ikon, this.metin);

  final IconData ikon;
  final String metin;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(
          metin,
          style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ======================================================================== okuyucu

enum _SayfaTuru { kapak, onsoz, icindekiler, faaliyet }

class _Sayfa {
  const _Sayfa(this.tur, [this.faaliyet, this.no = 0]);

  final _SayfaTuru tur;
  final Faaliyet? faaliyet;

  /// Faaliyet sayfasının kitaptaki sıra numarası (kapak = 1).
  final int no;
}

/// Kitapçık okuyucusu: kapak, önsöz, içindekiler ve her faaliyet için bir sayfa; yatay kaydırarak okunur.
class KitapcikOkuyucu extends StatefulWidget {
  const KitapcikOkuyucu({super.key, required this.veri, required this.kitap});

  final VeriKatmani veri;
  final Kitapcik kitap;

  @override
  State<KitapcikOkuyucu> createState() => _KitapcikOkuyucuState();
}

class _KitapcikOkuyucuState extends State<KitapcikOkuyucu> {
  final _kontrol = PageController();
  List<_Sayfa> _sayfalar = [];
  FaaliyetReferans _ref = FaaliyetReferans({});
  int _simdi = 0;
  int _eksik = 0;
  bool _yuklendi = false;

  Kitapcik get _k => widget.kitap;
  FaaliyetDeposu get _depo => widget.veri.faaliyetler;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final f = await _depo.numaralarla(_k.faaliyetler);
    final ref = await _depo.referans();
    if (!mounted) return;
    final s = <_Sayfa>[
      const _Sayfa(_SayfaTuru.kapak),
      if (_k.onsoz.isNotEmpty) const _Sayfa(_SayfaTuru.onsoz),
      if (_k.icindekiler && f.isNotEmpty) const _Sayfa(_SayfaTuru.icindekiler),
    ];
    var n = s.length;
    for (final x in f) {
      n++;
      s.add(_Sayfa(_SayfaTuru.faaliyet, x, n + 0));
    }
    setState(() {
      _sayfalar = s;
      _ref = FaaliyetReferans(ref);
      _eksik = _k.faaliyetler.length - f.length;
      _yuklendi = true;
    });
  }

  void _git(int i) => _kontrol.animateToPage(
    i,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final yazi = Color(renkDegeri(_k.yazi));
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.auto_stories_outlined,
            baslik: 'KİTAPÇIK',
            altBaslik: _k.baslikTek,
            eylemler: [
              if (_yuklendi && _sayfalar.length > 2)
                IconButton(
                  tooltip: 'Sayfaya git',
                  icon: const Icon(Icons.format_list_numbered_rounded),
                  onPressed: _sayfaListesi,
                ),
            ],
          ),
          Expanded(
            child: ColoredBox(
              color: acik
                  ? Color.lerp(zemin, yazi, 0.06)!
                  : Color.lerp(zemin, yazi, 0.12)!,
              child: !_yuklendi
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (_eksik > 0)
                          Container(
                            width: double.infinity,
                            color: cs.tertiaryContainer,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Text(
                              '$_eksik faaliyet cihaza henüz inmedi; eşitlenince sayfaları görünür.',
                              style: tema.textTheme.bodySmall,
                            ),
                          ),
                        Expanded(
                          child: PageView.builder(
                            controller: _kontrol,
                            itemCount: _sayfalar.length,
                            onPageChanged: (i) => setState(() => _simdi = i),
                            itemBuilder: (c, i) => Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                              child: _sayfaCiz(_sayfalar[i], i),
                            ),
                          ),
                        ),
                        _AltCubuk(
                          simdi: _simdi,
                          toplam: _sayfalar.length,
                          onceki: _simdi > 0 ? () => _git(_simdi - 1) : null,
                          sonraki: _simdi < _sayfalar.length - 1
                              ? () => _git(_simdi + 1)
                              : null,
                          yazi: yazi,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sayfaListesi() async {
    final i = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (c, kaydir) => ListView.builder(
          controller: kaydir,
          itemCount: _sayfalar.length,
          itemBuilder: (c, i) {
            final s = _sayfalar[i];
            final ad = switch (s.tur) {
              _SayfaTuru.kapak => 'Kapak',
              _SayfaTuru.onsoz => 'Önsöz',
              _SayfaTuru.icindekiler => 'İçindekiler',
              _SayfaTuru.faaliyet => faaliyetBasligi(s.faaliyet!.adi),
            };
            return ListTile(
              dense: true,
              selected: i == _simdi,
              leading: Text(
                '${i + 1}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              title: Text(ad, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(c, i),
            );
          },
        ),
      ),
    );
    if (i != null) _kontrol.jumpToPage(i);
  }

  Widget _sayfaCiz(_Sayfa s, int i) {
    switch (s.tur) {
      case _SayfaTuru.kapak:
        return _Kapak(kitap: _k, api: widget.veri.motor.api);
      case _SayfaTuru.onsoz:
        return _Kagit(
          kitap: _k,
          baslik: 'ÖNSÖZ',
          cocuk: SelectableText(
            _k.onsoz,
            textAlign: TextAlign.justify,
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
        );
      case _SayfaTuru.icindekiler:
        return _Kagit(
          kitap: _k,
          baslik: 'İÇİNDEKİLER',
          cocuk: Column(
            children: [
              for (var j = 0; j < _sayfalar.length; j++)
                if (_sayfalar[j].tur == _SayfaTuru.faaliyet)
                  InkWell(
                    onTap: () => _git(j),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              faaliyetBasligi(_sayfalar[j].faaliyet!.adi),
                              style: const TextStyle(fontSize: 13, height: 1.3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${j + 1}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      case _SayfaTuru.faaliyet:
        return _FaaliyetSayfasi(
          kitap: _k,
          faaliyet: s.faaliyet!,
          ref: _ref,
          veri: widget.veri,
          sayfaNo: i + 1,
        );
    }
  }
}

class _AltCubuk extends StatelessWidget {
  const _AltCubuk({
    required this.simdi,
    required this.toplam,
    required this.onceki,
    required this.sonraki,
    required this.yazi,
  });

  final int simdi;
  final int toplam;
  final VoidCallback? onceki;
  final VoidCallback? sonraki;
  final Color yazi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        6 + MediaQuery.paddingOf(context).bottom,
      ),
      color: cs.surface,
      child: Row(
        children: [
          IconButton(
            onPressed: onceki,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sayfa ${simdi + 1} / $toplam',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: toplam <= 1 ? 1 : (simdi + 1) / toplam,
                    minHeight: 3,
                    color: yazi,
                    backgroundColor: yazi.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: sonraki,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

/// Şablon renklerinde "kâğıt" yüzeyi: ince çerçeve, başlık şeridi.
class _Kagit extends StatelessWidget {
  const _Kagit({
    required this.kitap,
    required this.baslik,
    required this.cocuk,
  });

  final Kitapcik kitap;
  final String baslik;
  final Widget cocuk;

  @override
  Widget build(BuildContext context) {
    final yazi = Color(renkDegeri(kitap.yazi));
    final cizgi = Color(renkDegeri(kitap.cizgi));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cizgi, width: 1.4),
        boxShadow: programGolgesi(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              color: yazi,
              child: Text(
                baslik,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Expanded(
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Color(0xFF1F2937)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: cocuk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kapak extends StatelessWidget {
  const _Kapak({required this.kitap, required this.api});

  final Kitapcik kitap;
  final ApiIstemci api;

  /// Kapak fotoğrafı dosya adı "faaliyetNo-ad.jpg" biçimindedir.
  ({int no, String ad})? get _foto {
    for (final d in kitap.kapakFoto) {
      final m = RegExp(r'^(\d+)-').firstMatch(d);
      if (m != null) return (no: int.parse(m.group(1)!), ad: d);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final yazi = Color(renkDegeri(kitap.yazi));
    final cizgi = Color(renkDegeri(kitap.cizgi));
    final foto = _foto;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [yazi, Color.lerp(yazi, cizgi, 0.7)!],
        ),
        boxShadow: programGolgesi(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (foto != null)
              FutureBuilder<Uint8List?>(
                future: FaaliyetGorselleri.getir(
                  api,
                  'faaliyetler/dosya?no=${foto.no}&ad=${Uri.encodeQueryComponent(foto.ad)}&kucuk=1',
                ),
                builder: (c, s) => s.data == null
                    ? const SizedBox.shrink()
                    : Opacity(
                        opacity: 0.38,
                        child: Image.memory(s.data!, fit: BoxFit.cover),
                      ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    color: Colors.white70,
                    size: 40,
                  ),
                  const SizedBox(height: 22),
                  for (final s in kitap.baslikSatirlari)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        s,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  if (kitap.unvan.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      kitap.unvan,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    '${kitap.tarih.day} ${trAylar[kitap.tarih.month]} ${kitap.tarih.year}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${kitap.faaliyetler.length} faaliyet',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaaliyetSayfasi extends StatefulWidget {
  const _FaaliyetSayfasi({
    required this.kitap,
    required this.faaliyet,
    required this.ref,
    required this.veri,
    required this.sayfaNo,
  });

  final Kitapcik kitap;
  final Faaliyet faaliyet;
  final FaaliyetReferans ref;
  final VeriKatmani veri;
  final int sayfaNo;

  @override
  State<_FaaliyetSayfasi> createState() => _FaaliyetSayfasiState();
}

class _FaaliyetSayfasiState extends State<_FaaliyetSayfasi> {
  List<Map<String, dynamic>> _resimler = [];

  @override
  void initState() {
    super.initState();
    _fotolar();
  }

  Future<void> _fotolar() async {
    final no = widget.faaliyet.no;
    if (no == null) return;
    final depo = widget.veri.faaliyetler;
    Map<String, dynamic>? ek = await depo.ekOku(no);
    if (ek == null) {
      try {
        ek = await widget.veri.motor.faaliyetSenkron?.ayrintiGetir(no);
      } on ApiHata {
        return;
      }
    }
    if (!mounted || ek == null) return;
    const uzantilar = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'jfif'};
    setState(() {
      _resimler = [
        for (final x in (ek!['dosyalar'] as List? ?? const []))
          if (uzantilar.contains('${(x as Map)['tur']}'.toLowerCase()))
            Map<String, dynamic>.from(x),
      ].take(4).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.faaliyet;
    final k = widget.kitap;
    final api = widget.veri.motor.api;
    final yazi = Color(renkDegeri(k.yazi));
    final cizgi = Color(renkDegeri(k.cizgi));
    final kat = widget.ref.kategoriAdi(f.katno);
    return _Kagit(
      kitap: k,
      baslik: kat.isEmpty ? 'FAALİYET' : trBuyuk(kat),
      cocuk: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            faaliyetBasligi(f.adi),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: yazi,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${f.tarih.day} ${trAylar[f.tarih.month]} ${f.tarih.year}',
            style: TextStyle(
              fontSize: 12.5,
              color: cizgi,
              fontWeight: FontWeight.w600,
            ),
          ),
          Divider(color: cizgi.withValues(alpha: 0.5), height: 22),
          if (_resimler.isNotEmpty) ...[
            GridView.count(
              crossAxisCount: _resimler.length == 1 ? 1 : 2,
              childAspectRatio: _resimler.length == 1 ? 1.6 : 1.35,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < _resimler.length; i++)
                  GestureDetector(
                    onTap: () => gorselGezginiAc(
                      context,
                      api: api,
                      no: f.no!,
                      resimler: _resimler,
                      ilk: i,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: FutureBuilder<Uint8List?>(
                        future: FaaliyetGorselleri.getir(
                          api,
                          'faaliyetler/dosya?no=${f.no}&ad=${Uri.encodeQueryComponent('${_resimler[i]['ad']}')}&kucuk=1',
                        ),
                        builder: (c, s) => s.data == null
                            ? ColoredBox(
                                color: yazi.withValues(alpha: 0.08),
                                child: const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : Image.memory(s.data!, fit: BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          SelectableText(
            f.icerikDuz.trim(),
            textAlign: TextAlign.justify,
            style: const TextStyle(fontSize: 14.5, height: 1.55),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${widget.sayfaNo}',
              style: TextStyle(color: cizgi, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
