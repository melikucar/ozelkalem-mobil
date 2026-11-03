import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/yazi_formatlari.dart';
import '../../veri/program.dart' show gunBasi;
import '../../veri/rehber.dart';
import '../../veri/rehber_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../tema/tema.dart';
import '../../diger/cekince_esitle.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'cihaz_rehberi.dart';
import 'gorusme_detay.dart';
import 'gorusme_formu.dart';
import 'kisi_detay.dart';
import 'kisi_formu.dart';
import 'rehber_ayarlari.dart';
import 'rehber_ortak.dart';

enum _Sekme { kisiler, gorusmeler, kara }

/// Rehber: web "Rehber" modülünün (telefon rehberi, telefon görüşmeleri, kara liste) mobil karşılığı.
/// Kişiler: A–Z harf çubuğu, arama (ad, ünvan, telefon, e-posta, not), kategori süzgeci, yaklaşan doğum günleri.
/// Görüşmeler: özet sayaçları, durum / kaydeden / dönem süzgeçleri, "tekrar ara". Kara liste: tek dokunuşla çıkarma.
class RehberSayfasi extends StatefulWidget {
  const RehberSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<RehberSayfasi> createState() => _RehberSayfasiState();
}

class _RehberSayfasiState extends State<RehberSayfasi> {
  static const _sayfa = 60;

  _Sekme _s = _Sekme.kisiler;
  RehberReferans _ref = RehberReferans({});
  bool _yuklendi = false;

  // kişiler
  KisiFiltre _kf = const KisiFiltre();
  // Kişiler sanal liste: sayfalar (60'ar kişi) gerektikçe yüklenir; konumlar harf başına sayılardan hesaplanır (sabit satır yüksekliği).
  final Map<int, List<Kisi>> _kisiSayfalari = {};
  final Map<int, int> _kisiSayfaSurumu = {};
  final Set<int> _kisiYukleniyor = {};
  int _kisiSurumu = 0;
  List<_HarfBolumu> _bolumler = [];
  final _kisiKaydirma = ScrollController();
  bool _harfSurukleniyor = false;
  String _aktifHarf = '';
  int _kisiSonuc = 0;
  int _kisiToplam = 0;
  Map<String, int> _harfler = {};
  Set<int> _kisiSorunlu = {};
  List<(Kisi, int)> _dogumGunleri = [];

  // görüşmeler
  GorusmeFiltre _gf = const GorusmeFiltre();
  List<Gorusme> _gorusmeler = [];
  int _gorusmeSonuc = 0;
  Set<int> _gorusmeSorunlu = {};
  ({int toplam, int bugun, int hafta, int ay, int ulasilamayan})? _ozet;
  bool _gorusmeSonaGeldi = false;
  bool _gorusmeDaha = false;

  // kara liste
  List<Kisi> _kara = [];

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _bekle;

  RehberDeposu get _depo => widget.veri.rehber;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yenile);
    _kaydirma.addListener(_kaydirildi);
    _kisiKaydirma.addListener(_ustHarfiBul);
    _yenile();
  }

  @override
  void dispose() {
    _depo.removeListener(_yenile);
    _kaydirma.dispose();
    _kisiKaydirma.dispose();
    _bekle?.cancel();
    _arama.dispose();
    super.dispose();
  }

  void _kaydirildi() {
    if (_kaydirma.hasClients &&
        _kaydirma.position.pixels > _kaydirma.position.maxScrollExtent - 600) {
      _dahaFazla();
    }
  }

  Future<void> _yenile() async {
    final ref = await _depo.referans();
    switch (_s) {
      case _Sekme.kisiler:
        final f = _kf;
        final r = await Future.wait<Object?>([
          _depo.kisiSonucSayisi(f),
          _depo.kisiSayisi(),
          _depo.harfSayilari(f),
          _depo.sorunlular(RehberVarlik.kisi),
          _depo.yaklasanDogumGunleri(),
        ]);
        if (!mounted || !identical(f, _kf) || _s != _Sekme.kisiler) return;
        setState(() {
          _ref = RehberReferans(ref);
          _kisiSonuc = r[0] as int;
          _kisiToplam = r[1] as int;
          _harfler = r[2] as Map<String, int>;
          _kisiSorunlu = (r[3] as Map<int, dynamic>).keys.toSet();
          _dogumGunleri = r[4] as List<(Kisi, int)>;
          _bolumleriKur();
          _kisiSurumu++; // eski sayfalar yeniden okunana dek ekranda kalır (yanıp sönme olmaz)
          _yuklendi = true;
        });
        _kisiSayfasiYukle(0);
      case _Sekme.gorusmeler:
        final adet = _gorusmeler.length > _sayfa ? _gorusmeler.length : _sayfa;
        final f = _gf;
        final r = await Future.wait<Object?>([
          _depo.gorusmeListe(f, limit: adet),
          _depo.gorusmeSonucSayisi(f),
          _depo.sorunlular(RehberVarlik.gorusme),
          _depo.gorusmeOzeti(),
        ]);
        if (!mounted || !identical(f, _gf) || _s != _Sekme.gorusmeler) return;
        final liste = r[0] as List<Gorusme>;
        setState(() {
          _ref = RehberReferans(ref);
          _gorusmeler = liste;
          _gorusmeSonuc = r[1] as int;
          _gorusmeSorunlu = (r[2] as Map<int, dynamic>).keys.toSet();
          _ozet =
              r[3]
                  as ({
                    int toplam,
                    int bugun,
                    int hafta,
                    int ay,
                    int ulasilamayan,
                  });
          _gorusmeSonaGeldi = liste.length < adet;
          _yuklendi = true;
        });
      case _Sekme.kara:
        final kf = KisiFiltre(kelime: _kf.kelime, karaListe: true);
        final kara = await _depo.kisiListe(kf, limit: 500);
        final toplam = await _depo.kisiSayisi();
        if (!mounted || _s != _Sekme.kara) return;
        setState(() {
          _ref = RehberReferans(ref);
          _kara = kara;
          _kisiToplam = toplam;
          _yuklendi = true;
        });
    }
  }

  Future<void> _dahaFazla() async {
    if (_s == _Sekme.kisiler) {
      return; // kişiler sanal listedir; sayfalar gerektikçe yüklenir
    } else if (_s == _Sekme.gorusmeler) {
      if (_gorusmeDaha || _gorusmeSonaGeldi || !_yuklendi) return;
      _gorusmeDaha = true;
      final f = _gf;
      final yeni = await _depo.gorusmeListe(
        f,
        limit: _sayfa,
        offset: _gorusmeler.length,
      );
      if (mounted && identical(f, _gf)) {
        setState(() {
          _gorusmeler = [..._gorusmeler, ...yeni];
          _gorusmeSonaGeldi = yeni.length < _sayfa;
        });
      }
      _gorusmeDaha = false;
    }
  }

  void _kisiUygula(KisiFiltre f) {
    _kf = f;
    _kisiSayfalari.clear();
    _kisiSayfaSurumu.clear();
    _kisiYukleniyor.clear();
    _bolumler = [];
    _yenile();
    if (_kisiKaydirma.hasClients) _kisiKaydirma.jumpTo(0);
  }

  void _gorusmeUygula(GorusmeFiltre f) {
    _gf = f;
    _gorusmeler = [];
    _gorusmeSonaGeldi = false;
    _yenile();
    if (_kaydirma.hasClients) _kaydirma.jumpTo(0);
  }

  void _sekmeDegis(_Sekme s) {
    if (s == _s) return;
    setState(() {
      _s = s;
      _yuklendi = false;
    });
    if (_kaydirma.hasClients) _kaydirma.jumpTo(0);
    _yenile();
  }

  void _araDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(const Duration(milliseconds: 250), () {
      if (_s == _Sekme.gorusmeler) {
        _gorusmeUygula(_gf.kopya(kelime: v));
      } else {
        _kisiUygula(_kf.kopya(kelime: v, harf: ''));
      }
    });
  }

  void _aramayiKapat() {
    setState(() => _aramaAcik = false);
    if (_arama.text.isNotEmpty) {
      _arama.clear();
      if (_s == _Sekme.gorusmeler) {
        _gorusmeUygula(_gf.kopya(kelime: ''));
      } else {
        _kisiUygula(_kf.kopya(kelime: ''));
      }
    }
  }

  Future<void> _kisiAc(Kisi k) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => KisiDetay(veri: widget.veri, yerelId: k.yerelId!),
    ),
  );

  Future<void> _gorusmeAc(Gorusme g) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GorusmeDetay(veri: widget.veri, yerelId: g.yerelId!),
    ),
  );

  Future<void> _yeni() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _s == _Sekme.gorusmeler
          ? GorusmeFormu(veri: widget.veri)
          : KisiFormu(veri: widget.veri),
    ),
  );

  Future<void> _filtrePaneli() async {
    if (_s == _Sekme.gorusmeler) {
      final yeni = await showModalBottomSheet<GorusmeFiltre>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _GorusmeFiltrePaneli(f: _gf, ref: _ref),
      );
      if (yeni != null) _gorusmeUygula(yeni);
    } else {
      final yeni = await showModalBottomSheet<KisiFiltre>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _KisiFiltrePaneli(f: _kf, ref: _ref),
      );
      if (yeni != null) _kisiUygula(yeni);
    }
  }

  int get _etkinSuzgec => switch (_s) {
    _Sekme.gorusmeler => _gf.etkin + (_gf.durum != 0 ? 1 : 0),
    _Sekme.kisiler => _kf.katno != 0 ? 1 : 0,
    _Sekme.kara => 0,
  };

  String get _altBaslik {
    final bekleyen = widget.veri.motor.kuyrukSayisi > 0
        ? ' · ${widget.veri.motor.kuyrukSayisi} değişiklik gönderilecek'
        : '';
    if (_aramaAcik) {
      return switch (_s) {
        _Sekme.gorusmeler => 'Görüşmelerde ara',
        _ => 'Rehberde ara',
      };
    }
    return switch (_s) {
      _Sekme.kisiler =>
        '${_kisiSonuc == _kisiToplam ? '$_kisiToplam' : '$_kisiSonuc / $_kisiToplam'} kişi$bekleyen',
      _Sekme.gorusmeler => '$_gorusmeSonuc görüşme$bekleyen',
      _Sekme.kara => '${_kara.length} kayıt$bekleyen',
    };
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
    final motor = widget.veri.motor;
    return Scaffold(
      floatingActionButtonLocation: widget.sekme
          ? const BarUstuKonum()
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_s == _Sekme.kara || _harfSurukleniyor)
          ? null
          : KompaktDugme(
              etiket: _s == _Sekme.gorusmeler ? 'Yeni görüşme' : 'Yeni kişi',
              onPressed: _yeni,
            ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.contacts_outlined,
              baslik: 'Rehber',
              altBaslik: _altBaslik,
              eylemler: [
                IconButton(
                  tooltip: _aramaAcik ? 'Aramayı kapat' : 'Ara',
                  icon: Icon(
                    _aramaAcik ? Icons.close_rounded : Icons.search_rounded,
                  ),
                  onPressed: () {
                    if (_aramaAcik) {
                      _aramayiKapat();
                    } else {
                      setState(() => _aramaAcik = true);
                    }
                  },
                ),
                if (_s != _Sekme.kara)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Süzgeçler',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: _filtrePaneli,
                      ),
                      if (_etkinSuzgec > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDEC290),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_etkinSuzgec',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0C1C2F),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                PopupMenuButton<String>(
                  padding: const EdgeInsets.all(8),
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => v == 'cihaz'
                            ? CihazRehberi(veri: widget.veri)
                            : RehberAyarlari(veri: widget.veri),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'cihaz',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.download_for_offline_outlined),
                        title: Text('Telefon rehberinden aktar'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'kategori',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.category_outlined),
                        title: Text('Kategoriler'),
                      ),
                    ),
                  ],
                ),
              ],
              alt: _aramaAcik
                  ? HeroArama(
                      controller: _arama,
                      ipucu: _s == _Sekme.gorusmeler
                          ? 'Ad, konu, not ya da telefon ara'
                          : 'Ad, ünvan, telefon, e-posta ya da not ara',
                      degisti: _araDegisti,
                    )
                  : _SekmeSecici(
                      secili: _s,
                      kisi: _kisiToplam,
                      kara: _s == _Sekme.kara ? _kara.length : null,
                      sec: _sekmeDegis,
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
              child: CekinceEsitle(
                motor: motor,
                child: !_yuklendi
                    ? const Center(child: CircularProgressIndicator())
                    : switch (_s) {
                        _Sekme.kisiler => _kisiGovdesi(tema),
                        _Sekme.gorusmeler => _gorusmeGovdesi(tema),
                        _Sekme.kara => _karaGovdesi(tema),
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ kişiler

  Widget _bos(
    ThemeData tema,
    IconData ikon,
    String baslik,
    String alt, {
    Widget? eylem,
  }) => ListView(
    controller: _kaydirma,
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tema.colorScheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(ikon, size: 38, color: tema.colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              baslik,
              textAlign: TextAlign.center,
              style: tema.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              alt,
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
            ?eylem,
          ],
        ),
      ),
    ],
  );

  Widget _dogumGunuSeridi(ThemeData tema) {
    if (_dogumGunleri.isEmpty || _kf.kelime.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final (k, kalan) = _dogumGunleri.first;
    final d = k.sonrakiDogumGunu();
    final fazla = _dogumGunleri.length - 1;
    final yazi = kalan == 0
        ? 'Bugün doğum günü'
        : kalan == 1
        ? 'Yarın doğum günü'
        : '$kalan gün sonra doğum günü';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _kisiAc(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                const Icon(
                  Icons.cake_rounded,
                  color: Color(0xFFD97706),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: trBuyuk(k.adi),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              ' · $yazi${d?.yas != null ? ' (${d!.yas} yaş)' : ''}${fazla > 0 ? ' · +$fazla kişi daha' : ''}',
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodySmall?.copyWith(height: 1.3),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- sanal liste hesapları

  static const _baslikBoyu = 30.0;
  static const _seritBoyu = 66.0;

  bool get _seritVar => _dogumGunleri.isNotEmpty && _kf.kelime.isEmpty;

  void _bolumleriKur() {
    final liste = <_HarfBolumu>[];
    var oge = 0;
    var kisi = 0;
    for (final h in _HarfCubugu.hepsi) {
      final n = _harfler[h] ?? 0;
      if (n == 0) continue;
      liste.add(_HarfBolumu(h, oge, kisi, n));
      oge += 1 + n;
      kisi += n;
    }
    _bolumler = liste;
  }

  int get _ogeSayisi =>
      _bolumler.isEmpty ? 0 : _bolumler.last.ogeBas + 1 + _bolumler.last.adet;

  /// Bölümün listedeki piksel konumu (doğum günü şeridi dahil).
  double _bolumKonumu(_HarfBolumu b) =>
      (_seritVar ? _seritBoyu : 0) +
      _bolumler.indexOf(b) * _baslikBoyu +
      b.kisiBas * kisiSatirBoyu;

  void _harfeGit(String harf) {
    if (_bolumler.isEmpty) return;
    final sira = _HarfCubugu.hepsi.indexOf(harf);
    // bu harfte kişi yoksa kendisinden sonraki, o da yoksa sonuncu harfe gidilir
    _HarfBolumu? hedef;
    for (final b in _bolumler) {
      if (_HarfCubugu.hepsi.indexOf(b.harf) >= sira) {
        hedef = b;
        break;
      }
    }
    hedef ??= _bolumler.last;
    if (_aktifHarf != hedef.harf) {
      HapticFeedback.selectionClick();
      setState(() => _aktifHarf = hedef!.harf);
    }
    if (_kisiKaydirma.hasClients) {
      final p = _kisiKaydirma.position;
      _kisiKaydirma.jumpTo(
        _bolumKonumu(hedef).clamp(p.minScrollExtent, p.maxScrollExtent),
      );
    }
  }

  /// Kaydırırken ekranın en üstündeki harfi çubukta vurgular.
  void _ustHarfiBul() {
    if (_harfSurukleniyor || _bolumler.isEmpty || !_kisiKaydirma.hasClients) {
      return;
    }
    final y = _kisiKaydirma.offset - (_seritVar ? _seritBoyu : 0);
    var secilen = _bolumler.first;
    for (var i = 0; i < _bolumler.length; i++) {
      final b = _bolumler[i];
      if (i * _baslikBoyu + b.kisiBas * kisiSatirBoyu <= y + 1) secilen = b;
    }
    if (secilen.harf != _aktifHarf) setState(() => _aktifHarf = secilen.harf);
  }

  Future<void> _kisiSayfasiYukle(int p) async {
    if (!_kisiYukleniyor.add(p)) return;
    final f = _kf;
    final surum = _kisiSurumu;
    final l = await _depo.kisiListe(f, limit: _sayfa, offset: p * _sayfa);
    _kisiYukleniyor.remove(p);
    if (!mounted || !identical(f, _kf)) return;
    setState(() {
      _kisiSayfalari[p] = l;
      _kisiSayfaSurumu[p] = surum;
    });
  }

  Kisi? _kisiAl(int sira) {
    final p = sira ~/ _sayfa;
    if (_kisiSayfaSurumu[p] != _kisiSurumu) {
      // eksik ya da bayat sayfa: arka planda (yeniden) yükle, eldeki veriyi göstermeye devam et
      Future.microtask(() => _kisiSayfasiYukle(p));
    }
    final l = _kisiSayfalari[p];
    final i = sira - p * _sayfa;
    return (l != null && i < l.length) ? l[i] : null;
  }

  _HarfBolumu _bolumBul(int ogeSirasi) {
    var lo = 0;
    var hi = _bolumler.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_bolumler[mid].ogeBas <= ogeSirasi) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _bolumler[lo];
  }

  Widget _kisiGovdesi(ThemeData tema) {
    if (_ogeSayisi == 0) {
      final suzgerli = _kf.kelime.trim().isNotEmpty || _kf.katno != 0;
      return _bos(
        tema,
        suzgerli ? Icons.search_off_rounded : Icons.contacts_outlined,
        suzgerli ? 'Kriterlere uygun kişi yok' : 'Rehber boş',
        suzgerli
            ? 'Aramayı ya da süzgeçleri değiştirin.'
            : 'Yeni kişi ekleyin ya da telefon rehberinizden aktarın.',
        eylem: suzgerli
            ? TextButton(
                onPressed: () {
                  _arama.clear();
                  _kisiUygula(const KisiFiltre());
                },
                child: const Text('Süzgeçleri temizle'),
              )
            : null,
      );
    }
    final serit = _seritVar ? 1 : 0;
    final liste = ListView.builder(
      controller: _kisiKaydirma,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 140),
      itemCount: _ogeSayisi + serit,
      itemExtentBuilder: (i, _) {
        if (serit == 1 && i == 0) return _seritBoyu;
        final b = _bolumBul(i - serit);
        return (i - serit) == b.ogeBas ? _baslikBoyu : kisiSatirBoyu;
      },
      itemBuilder: (c, i) {
        if (serit == 1 && i == 0) {
          return SizedBox(height: _seritBoyu, child: _dogumGunuSeridi(tema));
        }
        final oge = i - serit;
        final b = _bolumBul(oge);
        if (oge == b.ogeBas) {
          return Container(
            height: _baslikBoyu,
            alignment: Alignment.centerLeft,
            color: tema.colorScheme.primary.withValues(alpha: 0.07),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              b.harf == '0-9' ? '0–9' : b.harf,
              style: tema.textTheme.labelLarge?.copyWith(
                color: tema.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }
        final k = _kisiAl(b.kisiBas + (oge - b.ogeBas - 1));
        if (k == null) return const SizedBox(height: kisiSatirBoyu);
        return KisiSatiri(
          kisi: k,
          kategoriAdi: _ref.kategoriAdi(k.katno),
          sorunlu: _kisiSorunlu.contains(k.yerelId),
          tikla: () => _kisiAc(k),
        );
      },
    );
    return Row(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: liste,
            ),
          ),
        ),
        _HarfCubugu(
          harfler: _harfler,
          aktif: _aktifHarf,
          surukleniyor: _harfSurukleniyor,
          git: _harfeGit,
          baslat: () => setState(() => _harfSurukleniyor = true),
          bitir: () => setState(() => _harfSurukleniyor = false),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ görüşmeler

  Widget _ozetSeridi(ThemeData tema) {
    final o = _ozet;
    if (o == null) return const SizedBox.shrink();
    Widget kutu(
      String etiket,
      int n,
      Color renk, {
      VoidCallback? tikla,
      bool secili = false,
    }) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tikla,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: renk.withValues(alpha: secili ? 0.22 : 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: renk.withValues(alpha: secili ? 0.7 : 0.25),
            ),
          ),
          child: Column(
            children: [
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color.lerp(
                    renk,
                    tema.brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    0.3,
                  ),
                ),
              ),
              Text(
                etiket,
                style: tema.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
    final cs = tema.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          kutu(
            'Bugün',
            o.bugun,
            cs.primary,
            secili: _gf.donem == GorusmeDonemi.bugun,
            tikla: () => _gorusmeUygula(
              _gf.kopya(
                donem: _gf.donem == GorusmeDonemi.bugun
                    ? GorusmeDonemi.tumu
                    : GorusmeDonemi.bugun,
              ),
            ),
          ),
          const SizedBox(width: 8),
          kutu('Bu hafta', o.hafta, cs.primary),
          const SizedBox(width: 8),
          kutu('Bu ay', o.ay, cs.primary),
          const SizedBox(width: 8),
          kutu(
            'Ulaşılamayan',
            o.ulasilamayan,
            const Color(0xFFD97706),
            secili: _gf.durum == 2,
            tikla: () =>
                _gorusmeUygula(_gf.kopya(durum: _gf.durum == 2 ? 0 : 2)),
          ),
        ],
      ),
    );
  }

  Widget _gorusmeGovdesi(ThemeData tema) {
    if (_gorusmeler.isEmpty) {
      final suzgerli =
          _gf.kelime.trim().isNotEmpty || _gf.durum != 0 || _gf.etkin > 0;
      return _bos(
        tema,
        suzgerli ? Icons.search_off_rounded : Icons.phone_in_talk_outlined,
        suzgerli ? 'Kriterlere uygun görüşme yok' : 'Henüz görüşme kaydı yok',
        suzgerli
            ? 'Aramayı ya da süzgeçleri değiştirin.'
            : 'Yaptığınız ya da aldığınız aramaları buraya kaydedin.',
        eylem: suzgerli
            ? TextButton(
                onPressed: () {
                  _arama.clear();
                  _gorusmeUygula(const GorusmeFiltre());
                },
                child: const Text('Süzgeçleri temizle'),
              )
            : null,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          controller: _kaydirma,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
          itemCount: _gorusmeler.length + 1 + (_gorusmeSonaGeldi ? 0 : 1),
          itemBuilder: (c, i) {
            if (i == 0) return _ozetSeridi(tema);
            i -= 1;
            if (i >= _gorusmeler.length) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }
            final g = _gorusmeler[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GorusmeKarti(
                gorusme: g,
                ref: _ref,
                sorunlu: _gorusmeSorunlu.contains(g.yerelId),
                tikla: () => _gorusmeAc(g),
              ),
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ kara liste

  Future<void> _karaCikar(Kisi k) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${trBuyuk(k.adi)} kara listeden çıkarılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (onay == true) await _depo.karaDegistir(k.yerelId!, false);
  }

  Widget _karaGovdesi(ThemeData tema) {
    if (_kara.isEmpty) {
      return _bos(
        tema,
        Icons.shield_outlined,
        'Kara liste boş',
        'Bir kişinin ayrıntısından ya da görüşme kaydederken kara listeye alabilirsiniz.',
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          controller: _kaydirma,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          itemCount: _kara.length,
          itemBuilder: (c, i) {
            final k = _kara[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: programGolgesi(context),
                ),
                child: Material(
                  color: tema.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _kisiAc(k),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.block_rounded,
                            color: Color(0xFFE11D48),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trBuyuk(k.adi),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  [
                                    if (k.unvan.trim().isNotEmpty)
                                      k.unvan.trim(),
                                    if (k.anaTelefon.isNotEmpty) k.anaTelefon,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: tema.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _karaCikar(k),
                            child: const Text('Çıkar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ======================================================================== küçük bileşenler

/// Hero içinde Kişiler / Görüşmeler / Kara liste sekmeleri.
class _SekmeSecici extends StatelessWidget {
  const _SekmeSecici({
    required this.secili,
    required this.kisi,
    required this.sec,
    this.kara,
  });

  final _Sekme secili;
  final int kisi;
  final int? kara;
  final ValueChanged<_Sekme> sec;

  @override
  Widget build(BuildContext context) {
    const liste = _Sekme.values;
    String ad(_Sekme s) => switch (s) {
      _Sekme.kisiler => 'Kişiler',
      _Sekme.gorusmeler => 'Görüşmeler',
      _Sekme.kara => 'Kara liste',
    };
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: LayoutBuilder(
        builder: (context, k) {
          final w = k.maxWidth / liste.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                left: liste.indexOf(secili) * w,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final s in liste)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => sec(s),
                        child: Center(
                          child: Text(
                            ad(s),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: s == secili
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: s == secili
                                  ? Marka.lacivert
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bir harfin liste içindeki konumu: başlığın öğe sırası, ilk kişinin sırası ve kişi sayısı.
class _HarfBolumu {
  const _HarfBolumu(this.harf, this.ogeBas, this.kisiBas, this.adet);

  final String harf;
  final int ogeBas;
  final int kisiBas;
  final int adet;
}

/// Sağ kenarda A–Z harf çubuğu: parmakla basılı tutup aşağı yukarı sürüklenir; harfler parmağın etrafında büyüyüp yana kayar,
/// büyük bir balon harfi gösterir ve liste aynı anda o harfe iner. Kişi bulunmayan harfler soluk görünür.
class _HarfCubugu extends StatelessWidget {
  const _HarfCubugu({
    required this.harfler,
    required this.aktif,
    required this.surukleniyor,
    required this.git,
    required this.baslat,
    required this.bitir,
  });

  final Map<String, int> harfler;
  final String aktif;
  final bool surukleniyor;
  final ValueChanged<String> git;
  final VoidCallback baslat;
  final VoidCallback bitir;

  static const hepsi = [
    '0-9',
    'A',
    'B',
    'C',
    'Ç',
    'D',
    'E',
    'F',
    'G',
    'Ğ',
    'H',
    'I',
    'İ',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'Ö',
    'P',
    'R',
    'S',
    'Ş',
    'T',
    'U',
    'Ü',
    'V',
    'Y',
    'Z',
    '#',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 30,
      child: LayoutBuilder(
        builder: (context, k) {
          final h = k.maxHeight;
          final adim = h / hepsi.length;
          int sira(double dy) => (dy / adim).floor().clamp(0, hepsi.length - 1);
          final aktifSira = hepsi.indexOf(aktif);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              baslat();
              git(hepsi[sira(d.localPosition.dy)]);
            },
            onTapUp: (_) => bitir(),
            onTapCancel: bitir,
            onVerticalDragStart: (d) {
              baslat();
              git(hepsi[sira(d.localPosition.dy)]);
            },
            onVerticalDragUpdate: (d) => git(hepsi[sira(d.localPosition.dy)]),
            onVerticalDragEnd: (_) => bitir(),
            onVerticalDragCancel: bitir,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < hepsi.length; i++)
                  Positioned(
                    top: i * adim,
                    height: adim,
                    right: 0,
                    width: 30,
                    child: _HarfOgesi(
                      harf: hepsi[i],
                      var_: (harfler[hepsi[i]] ?? 0) > 0,
                      uzaklik: aktifSira < 0 || !surukleniyor
                          ? 99
                          : (i - aktifSira).abs(),
                      secili: hepsi[i] == aktif,
                      cs: cs,
                    ),
                  ),
                if (surukleniyor && aktifSira >= 0)
                  Positioned(
                    right: 62,
                    top: (aktifSira * adim + adim / 2 - 32).clamp(0.0, h - 64),
                    child: _Balon(
                      harf: aktif == '0-9' ? '0–9' : aktif,
                      adet: harfler[aktif] ?? 0,
                      cs: cs,
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

class _HarfOgesi extends StatelessWidget {
  const _HarfOgesi({
    required this.harf,
    required this.var_,
    required this.uzaklik,
    required this.secili,
    required this.cs,
  });

  final String harf;
  final bool var_;
  final int uzaklik;
  final bool secili;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    // parmağa yakın harfler büyür ve sola doğru dalga gibi kayar
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
        width: 20,
        alignment: Alignment.center,
        decoration: secili
            ? BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(9),
              )
            : null,
        child: Text(
          harf == '0-9' ? '#' : harf,
          style: TextStyle(
            fontSize: 11,
            height: 1.1,
            fontWeight: var_ ? FontWeight.w700 : FontWeight.w400,
            color: secili
                ? cs.onPrimary
                : var_
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// Sürüklerken harfin yanında beliren büyük balon.
class _Balon extends StatelessWidget {
  const _Balon({required this.harf, required this.adet, required this.cs});

  final String harf;
  final int adet;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(harf),
      tween: Tween(begin: 0.7, end: 1),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      builder: (c, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            bottomLeft: Radius.circular(32),
            topRight: Radius.circular(32),
            bottomRight: Radius.circular(8),
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
          children: [
            Text(
              harf,
              style: TextStyle(
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w700,
                color: cs.onPrimary,
              ),
            ),
            Text(
              '$adet kişi',
              style: TextStyle(
                fontSize: 9.5,
                color: cs.onPrimary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KisiFiltrePaneli extends StatefulWidget {
  const _KisiFiltrePaneli({required this.f, required this.ref});

  final KisiFiltre f;
  final RehberReferans ref;

  @override
  State<_KisiFiltrePaneli> createState() => _KisiFiltrePaneliState();
}

class _KisiFiltrePaneliState extends State<_KisiFiltrePaneli> {
  late KisiFiltre _f = widget.f;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Süzgeçler', style: tema.textTheme.titleMedium),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue:
                  widget.ref.kategoriler.any((x) => x['no'] == _f.katno)
                  ? _f.katno
                  : 0,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Hepsi')),
                for (final k in widget.ref.kategoriler)
                  DropdownMenuItem(
                    value: k['no'] as int,
                    child: Text('${k['adi']}'),
                  ),
              ],
              onChanged: (v) => setState(() => _f = _f.kopya(katno: v ?? 0)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, KisiFiltre(kelime: _f.kelime)),
                    child: const Text('Temizle'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _f),
                    child: const Text('Uygula'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GorusmeFiltrePaneli extends StatefulWidget {
  const _GorusmeFiltrePaneli({required this.f, required this.ref});

  final GorusmeFiltre f;
  final RehberReferans ref;

  @override
  State<_GorusmeFiltrePaneli> createState() => _GorusmeFiltrePaneliState();
}

class _GorusmeFiltrePaneliState extends State<_GorusmeFiltrePaneli> {
  late GorusmeFiltre _f = widget.f;

  Future<void> _aralik() async {
    final bugun = gunBasi(DateTime.now());
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: (_f.bas != null && _f.bit != null)
          ? DateTimeRange(start: _f.bas!, end: _f.bit!)
          : DateTimeRange(start: bugun, end: bugun),
    );
    if (r != null) {
      setState(
        () =>
            _f = _f.kopya(donem: GorusmeDonemi.ozel, bas: r.start, bit: r.end),
      );
    }
  }

  String _gun(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ref = widget.ref;
    const donemler = {
      GorusmeDonemi.tumu: 'Tümü',
      GorusmeDonemi.bugun: 'Bugün',
      GorusmeDonemi.son7: 'Son 7 gün',
      GorusmeDonemi.son30: 'Son 30 gün',
      GorusmeDonemi.ozel: 'Tarih aralığı…',
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Süzgeçler', style: tema.textTheme.titleMedium),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: ref.durumlar.any((x) => x['no'] == _f.durum)
                    ? _f.durum
                    : 0,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Durum',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Hepsi')),
                  for (final d in ref.durumlar)
                    DropdownMenuItem(
                      value: d['no'] as int,
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: gorusmeDurumRengi(d['no'] as int),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '${d['adi']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _f = _f.kopya(durum: v ?? 0)),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: ref.kaydedenler.any((x) => x['no'] == _f.kaydeden)
                    ? _f.kaydeden
                    : 0,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Kaydeden',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Hepsi')),
                  for (final k in ref.kaydedenler)
                    DropdownMenuItem(
                      value: k['no'] as int,
                      child: Text('${k['adi']}'),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _f = _f.kopya(kaydeden: v ?? 0)),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<GorusmeDonemi>(
                initialValue: _f.donem,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Dönem',
                  prefixIcon: Icon(Icons.date_range_outlined),
                ),
                items: [
                  for (final e in donemler.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v == GorusmeDonemi.ozel) {
                    _aralik();
                  } else {
                    setState(
                      () => _f = _f.kopya(donem: v ?? GorusmeDonemi.tumu),
                    );
                  }
                },
              ),
              if (_f.donem == GorusmeDonemi.ozel && _f.bas != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton.icon(
                    onPressed: _aralik,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: Text('${_gun(_f.bas!)} – ${_gun(_f.bit!)}'),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        GorusmeFiltre(kelime: _f.kelime),
                      ),
                      child: const Text('Temizle'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _f),
                      child: const Text('Uygula'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
