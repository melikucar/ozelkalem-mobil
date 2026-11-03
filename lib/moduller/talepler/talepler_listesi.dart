import '../../diger/kompakt_dugme.dart';
import '../../diger/senkron_durumu.dart';
import '../../diger/cekince_esitle.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tema/tema.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/talep.dart';
import '../../veri/talep_deposu.dart';
import '../../veri/talep_filtre.dart';
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import 'talep_detay.dart';
import 'talep_filtre_paneli.dart';
import 'talep_formu.dart';

/// Talepler: lacivert hero (başlık + arama), filtre/sıralama/görünüm çubuğu, sayılı durum çipleri,
/// etkin filtre etiketleri ve premium talep kartları. Yalnızca yerel veritabanını okur; her değişiklik anında uygulanır.
class TaleplerListesi extends StatefulWidget {
  const TaleplerListesi({
    super.key,
    required this.veri,
    this.sekme = false,
    this.durumIstegi,
  });

  final VeriKatmani veri;

  /// Alt gezinti sekmesi olarak gömülü: geri oku gösterilmez.
  final bool sekme;

  /// Başka bir ekrandan (ana sayfa) gelen "şu durumdaki talepleri göster" isteği.
  final ValueNotifier<int?>? durumIstegi;

  @override
  State<TaleplerListesi> createState() => _TaleplerListesiState();
}

class _TaleplerListesiState extends State<TaleplerListesi> {
  static const _sayfa = 60;

  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _bekle;
  bool _aramaAcik = false;

  TalepFiltre _f = const TalepFiltre();
  List<Talep> _kayitlar = [];
  Map<int, ({String adi, String? renk})> _durumlar = {};
  Map<int, String> _kategoriler = {};
  Map<int, String> _ilceAdlari = {};
  Map<int, String> _kaydedenAdlari = {};
  Map<int, KuyrukOp> _sorunlu = {};
  int _toplam = 0;
  int _sonuc = 0;
  bool _sonaGeldi = false;
  bool _yukleniyor = false;
  bool _kart = false;

  TalepDeposu get _depo => widget.veri.talepler;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yenile);
    widget.durumIstegi?.addListener(_durumIstegiGeldi);
    // Sekme istekle birlikte ilk kez kuruluyorsa (ana sayfadan dokunuş) istek dinleyiciden önce gelmiş olabilir
    WidgetsBinding.instance.addPostFrameCallback((_) => _durumIstegiGeldi());
    _kaydirma.addListener(() {
      if (_kaydirma.position.extentAfter < 600) _dahaFazla();
    });
    _depo.meta('talep_gorunum').then((v) {
      if (mounted && v == 'kart') setState(() => _kart = true);
    });
    _adlariYukle();
    _yenile();
  }

  @override
  void dispose() {
    _depo.removeListener(_yenile);
    widget.durumIstegi?.removeListener(_durumIstegiGeldi);
    _bekle?.cancel();
    _arama.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  void _durumIstegiGeldi() {
    final no = widget.durumIstegi?.value;
    if (no == null) return;
    widget.durumIstegi!.value = null;
    _arama.clear();
    _uygula(TalepFiltre(durumlar: {no}));
  }

  Future<void> _adlariYukle() async {
    final ilce = await _depo.ilceSecenekleri();
    final kaydeden = await _depo.kaydedenler();
    if (!mounted) return;
    setState(() {
      _ilceAdlari = {for (final i in ilce) i.id: i.ad};
      _kaydedenAdlari = {for (final k in kaydeden) k.no: k.adi};
    });
  }

  Future<void> _yenile() async {
    final adet = _kayitlar.length > _sayfa ? _kayitlar.length : _sayfa;
    final f = _f;
    final liste = await _depo.liste(filtre: f, limit: adet);
    final durumlar = await _depo.durumlar();
    final kategoriler = await _depo.kategoriler();
    final sorunlu = await _depo.sorunlular();
    final toplam = await _depo.sayi();
    final sonuc = await _depo.sonucSayisi(f);
    if (!mounted || !identical(f, _f)) return;
    setState(() {
      _kayitlar = liste;
      _durumlar = durumlar;
      _kategoriler = kategoriler;
      _sorunlu = sorunlu;
      _toplam = toplam;
      _sonuc = sonuc;
      _sonaGeldi = liste.length < adet;
    });
  }

  Future<void> _dahaFazla() async {
    if (_yukleniyor || _sonaGeldi) return;
    _yukleniyor = true;
    final f = _f;
    final liste = await _depo.liste(
      filtre: f,
      limit: _sayfa,
      offset: _kayitlar.length,
    );
    if (mounted && identical(f, _f)) {
      setState(() {
        _kayitlar = [..._kayitlar, ...liste];
        _sonaGeldi = liste.length < _sayfa;
      });
    }
    _yukleniyor = false;
  }

  void _uygula(TalepFiltre yeni) {
    _f = yeni;
    _kayitlar = [];
    _yenile();
    if (_kaydirma.hasClients) _kaydirma.jumpTo(0);
  }

  void _aramaDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(
      const Duration(milliseconds: 220),
      () => _uygula(_f.kopya(arama: v)),
    );
  }

  Future<void> _panel() async {
    final yeni = await talepFiltrePaneli(
      context,
      depo: _depo,
      mevcut: _f,
      durumlar: _durumlar,
      kategoriler: _kategoriler,
    );
    if (yeni != null) _uygula(yeni);
  }

  void _gorunum(bool kart) {
    setState(() => _kart = kart);
    _depo.metaYaz('talep_gorunum', kart ? 'kart' : 'liste');
  }

  Future<void> _detay(Talep t) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TalepDetay(veri: widget.veri, yerelId: t.yerelId!),
    ),
  );

  Future<void> _yeni() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => TalepFormu(veri: widget.veri)));

  Future<void> _ara(String telefon) async {
    final r = telefonRakamlari(telefon);
    if (r.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: '+$r'));
  }

  /// Satırları güne göre gruplar: [String başlık | Talep]. Tarih dışı sıralamada grup başlığı yok.
  List<Object> _oge() {
    if (_f.sirala != TalepSirala.yeni && _f.sirala != TalepSirala.eski) {
      return [..._kayitlar];
    }
    final cikti = <Object>[];
    String? son;
    for (final t in _kayitlar) {
      final e = gunEtiketi(t.tarih);
      if (e != son) {
        cikti.add(e);
        son = e;
      }
      cikti.add(t);
    }
    return cikti;
  }

  /// Panelden ayarlanmış filtreler için kaldırılabilir etiketler.
  List<({String ad, VoidCallback kaldir})> _etiketler() {
    final f = _f;
    return [
      if (f.kategoriler.isNotEmpty)
        (
          ad: f.kategoriler.map((k) => _kategoriler[k] ?? '$k').join(', '),
          kaldir: () => _uygula(f.kopya(kategoriler: const {})),
        ),
      if (f.ilce != null)
        (
          ad: _ilceAdlari[f.ilce] ?? 'İlçe ${f.ilce}',
          kaldir: () => _uygula(f.kopya(ilce: null)),
        ),
      if (f.kaydeden != null)
        (
          ad: 'Kaydeden: ${_kaydedenAdlari[f.kaydeden] ?? f.kaydeden}',
          kaldir: () => _uygula(f.kopya(kaydeden: null)),
        ),
      if (f.telefon.trim().isNotEmpty)
        (
          ad: 'Tel: ${f.telefon.trim()}',
          kaldir: () => _uygula(f.kopya(telefon: '')),
        ),
      if (f.bas != null || f.bit != null)
        (
          ad: [uzunTarih(f.bas) ?? '…', uzunTarih(f.bit) ?? '…'].join(' – '),
          kaldir: () => _uygula(f.kopya(bas: null, bit: null)),
        ),
      if (f.bekleyen)
        (
          ad: 'Gönderilmeyi bekleyen',
          kaldir: () => _uygula(f.kopya(bekleyen: false)),
        ),
      if (f.hatirlatici)
        (
          ad: 'Hatırlatıcılı',
          kaldir: () => _uygula(f.kopya(hatirlatici: false)),
        ),
    ];
  }

  void _hepsiniTemizle() {
    _arama.clear();
    _uygula(const TalepFiltre());
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final oge = _oge();
    final motor = widget.veri.motor;
    final vurgu = tema.colorScheme.primary;
    final etiketler = _etiketler();
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(
      zemin,
      tema.colorScheme.primary,
      acik ? 0.10 : 0.14,
    )!;

    final araSeritler = <Widget>[
      SliverToBoxAdapter(child: SenkronSeridi(motor: motor)),
      if (etiketler.isNotEmpty)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              children: [
                for (final e in etiketler)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(e.ad),
                      visualDensity: VisualDensity.compact,
                      onDeleted: e.kaldir,
                      onPressed: _panel,
                    ),
                  ),
                TextButton(
                  onPressed: _hepsiniTemizle,
                  child: const Text('Tümünü temizle'),
                ),
              ],
            ),
          ),
        ),
    ];

    Widget govde;
    if (oge.isEmpty) {
      govde = SliverFillRemaining(
        hasScrollBody: false,
        child: _Bos(
          yukleniyor: motor.ilkYukleme,
          daraltiyor: _f.daraltiyor,
          temizle: _hepsiniTemizle,
        ),
      );
    } else if (_kart) {
      final kartlar = [
        for (final o in oge)
          if (o is Talep) o,
      ];
      govde = SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 360,
            mainAxisExtent: 168,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: kartlar.length,
          itemBuilder: (context, i) {
            final t = kartlar[i];
            return TalepKarti(
              talep: t,
              durum: _durumlar[t.durum],
              kategori: _kategoriler[t.katno],
              sorun: _sorunlu[t.yerelId],
              kompakt: true,
              tikla: () => _detay(t),
              ara: () => _ara(t.telefon),
            );
          },
        ),
      );
    } else {
      govde = SliverPadding(
        padding: const EdgeInsets.only(bottom: 110),
        sliver: SliverList.builder(
          itemCount: oge.length,
          itemBuilder: (context, i) {
            final o = oge[i];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: o is String
                    ? _GunBasligi(o)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
                        child: TalepKarti(
                          talep: o as Talep,
                          durum: _durumlar[o.durum],
                          kategori: _kategoriler[o.katno],
                          sorun: _sorunlu[o.yerelId],
                          tikla: () => _detay(o),
                          ara: () => _ara(o.telefon),
                        ),
                      ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      floatingActionButtonLocation: widget.sekme
          ? const BarUstuKonum()
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: KompaktDugme(
        etiket: 'Yeni talep',
        onPressed: _yeni,
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.assignment_outlined,
              baslik: 'Talepler',
              altBaslik:
                  '${_sonuc == _toplam ? '$_toplam kayıt' : '$_sonuc / $_toplam kayıt'}${motor.kuyrukSayisi > 0 ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek' : ''}',
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
                      _uygula(_f.kopya(arama: ''));
                    }
                  },
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Filtrele',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: _panel,
                    ),
                    if (_f.panelSayisi > 0)
                      Positioned(
                        right: 6,
                        top: 6,
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
                            '${_f.panelSayisi}',
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
                PopupMenuButton<TalepSirala>(
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Sırala: ${_f.sirala.etiket}',
                  icon: const Icon(Icons.swap_vert_rounded),
                  initialValue: _f.sirala,
                  onSelected: (s) => _uygula(_f.kopya(sirala: s)),
                  itemBuilder: (_) => [
                    for (final s in TalepSirala.values)
                      PopupMenuItem(
                        value: s,
                        child: Row(
                          children: [
                            Icon(
                              s == _f.sirala
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 18,
                              color: s == _f.sirala ? vurgu : null,
                            ),
                            const SizedBox(width: 10),
                            Text(s.etiket),
                          ],
                        ),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: _kart ? 'Liste görünümü' : 'Kart görünümü',
                  icon: Icon(
                    _kart
                        ? Icons.view_agenda_outlined
                        : Icons.grid_view_rounded,
                  ),
                  onPressed: () => _gorunum(!_kart),
                ),
              ],
              alt: (_aramaAcik || _arama.text.isNotEmpty)
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Ad, telefon, T.C., içerik veya kurum ara',
                      degisti: _aramaDegisti,
                    )
                  : null,
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.35, 1],
                ),
              ),
              child: CekinceEsitle(
                motor: motor,
                child: CustomScrollView(
                  controller: _kaydirma,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [...araSeritler, govde],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color? talepRengi(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

class _GunBasligi extends StatelessWidget {
  const _GunBasligi(this.metin);

  final String metin;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              color: tema.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              metin,
              style: tema.textTheme.labelMedium?.copyWith(
                color: tema.colorScheme.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: tema.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bos extends StatelessWidget {
  const _Bos({
    required this.yukleniyor,
    required this.daraltiyor,
    required this.temizle,
  });

  final bool yukleniyor;
  final bool daraltiyor;
  final VoidCallback temizle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 140),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tema.colorScheme.primary.withValues(alpha: 0.10),
            ),
            child: Icon(
              yukleniyor
                  ? Icons.downloading_rounded
                  : Icons.manage_search_rounded,
              size: 40,
              color: tema.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            yukleniyor ? 'Talepler yükleniyor…' : 'Talep bulunamadı',
            style: tema.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!yukleniyor) ...[
            const SizedBox(height: 6),
            Text(
              daraltiyor
                  ? 'Seçili filtrelere uyan kayıt yok.'
                  : 'Henüz talep kaydı yok.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (daraltiyor && !yukleniyor) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: temizle,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Filtreleri temizle'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Premium talep kartı: durum renginde şerit, ad ve telefon, göreli zaman, içerik özeti,
/// durum/kategori/referans etiketleri ve hızlı arama düğmesi. [kompakt] kart ızgarası içindir.
class TalepKarti extends StatelessWidget {
  const TalepKarti({
    super.key,
    required this.talep,
    required this.durum,
    required this.tikla,
    required this.ara,
    this.kategori,
    this.sorun,
    this.kompakt = false,
  });

  final Talep talep;
  final ({String adi, String? renk})? durum;
  final String? kategori;
  final KuyrukOp? sorun;
  final bool kompakt;
  final VoidCallback tikla;
  final VoidCallback ara;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final renk = talepRengi(durum?.renk) ?? tema.colorScheme.outline;
    final koyuRenk = acik
        ? Color.lerp(renk, Colors.black, 0.38)!
        : Color.lerp(renk, Colors.white, 0.45)!;
    final ozet = htmlDuz(talep.s('icerik')).replaceAll('\n', ' ');
    final referans = talep.s('referans').trim();
    final goreli = goreliGun(talep.tarih);

    Widget? sync;
    if (sorun != null) {
      final cakisma = sorun!.durum == 'cakisma';
      sync = Icon(
        cakisma ? Icons.warning_amber_rounded : Icons.error_rounded,
        size: 19,
        color: cakisma ? Colors.amber.shade800 : tema.colorScheme.error,
      );
    } else if (talep.bekleyen) {
      sync = Icon(
        Icons.cloud_upload_outlined,
        size: 18,
        color: tema.colorScheme.outline,
      );
    }

    Widget etiket(IconData ikon, String metin, {int en = 150}) => Container(
      constraints: BoxConstraints(maxWidth: en.toDouble()),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tema.colorScheme.onSurface.withValues(alpha: acik ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 13, color: tema.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              metin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    final etiketler = <Widget>[
      if (durum != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: renk.withValues(alpha: acik ? 0.15 : 0.28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                durum!.adi,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: koyuRenk,
                ),
              ),
            ],
          ),
        ),
      if (kategori != null && kategori!.isNotEmpty)
        etiket(Icons.category_outlined, kategori!),
      if (!kompakt && referans.isNotEmpty)
        etiket(Icons.person_outline_rounded, referans, en: 170),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (acik ? Marka.lacivert : Colors.black).withValues(
              alpha: acik ? 0.08 : 0.35,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: tema.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tikla,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [renk, renk.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 13),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                talep.adBuyuk.isEmpty
                                    ? '(adsız)'
                                    : talep.adBuyuk,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.5,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  if (talep.no != null) '#${talep.no}',
                                  if (goreli.isNotEmpty) goreli,
                                ].join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.bodySmall?.copyWith(
                                  color: tema.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sync != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6, top: 2),
                            child: sync,
                          ),
                        if (talep.telefon.isNotEmpty && !kompakt)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              tooltip: talep.telefon,
                              padding: EdgeInsets.zero,
                              onPressed: ara,
                              icon: Icon(
                                Icons.phone_in_talk_rounded,
                                size: 20,
                                color: tema.colorScheme.primary,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: tema.colorScheme.primary
                                    .withValues(alpha: 0.10),
                              ),
                            ),
                          )
                        else if (!kompakt)
                          const SizedBox(width: 6),
                      ],
                    ),
                    if (ozet.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          ozet,
                          maxLines: kompakt ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: tema.colorScheme.onSurface.withValues(
                              alpha: 0.82,
                            ),
                            fontSize: 13.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    if (etiketler.isNotEmpty || kompakt) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: etiketler,
                            ),
                          ),
                          if (kompakt && talep.telefon.isNotEmpty)
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: IconButton(
                                tooltip: talep.telefon,
                                padding: EdgeInsets.zero,
                                onPressed: ara,
                                icon: Icon(
                                  Icons.phone_in_talk_rounded,
                                  size: 18,
                                  color: tema.colorScheme.primary,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: tema.colorScheme.primary
                                      .withValues(alpha: 0.10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kompakt satır: ad, telefon, içerik özeti; sağda durum etiketi ve eşitleme simgesi.
class TalepSatiri extends StatelessWidget {
  const TalepSatiri({
    super.key,
    required this.talep,
    required this.durum,
    required this.sorun,
    required this.ayrac,
    required this.tikla,
  });

  final Talep talep;
  final ({String adi, String? renk})? durum;
  final KuyrukOp? sorun;
  final bool ayrac;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final renk = talepRengi(durum?.renk) ?? tema.colorScheme.outline;
    final ozet = htmlDuz(talep.s('icerik')).replaceAll('\n', ' ');
    final acik = tema.brightness == Brightness.light;

    Widget? durumIkonu;
    if (sorun != null) {
      durumIkonu = Icon(
        sorun!.durum == 'cakisma'
            ? Icons.warning_amber_rounded
            : Icons.error_rounded,
        size: 18,
        color: sorun!.durum == 'cakisma'
            ? Colors.amber.shade800
            : tema.colorScheme.error,
      );
    } else if (talep.bekleyen) {
      durumIkonu = Icon(
        Icons.cloud_upload_outlined,
        size: 17,
        color: tema.colorScheme.outline,
      );
    }

    return InkWell(
      onTap: tikla,
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 11, 14, 11),
                decoration: BoxDecoration(
                  border: ayrac
                      ? Border(
                          bottom: BorderSide(
                            color: tema.colorScheme.outlineVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            talep.adBuyuk.isEmpty ? '(adsız)' : talep.adBuyuk,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_outlined,
                                size: 13,
                                color: tema.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  talep.telefon.isEmpty ? '—' : talep.telefon,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: tema.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (ozet.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                ozet,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.bodySmall?.copyWith(
                                  color: tema.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.85),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (durum != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: renk.withValues(alpha: acik ? 0.14 : 0.26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              durum!.adi,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: acik
                                    ? Color.lerp(renk, Colors.black, 0.4)
                                    : Color.lerp(renk, Colors.white, 0.5),
                              ),
                            ),
                          ),
                        if (durumIkonu != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: durumIkonu,
                          ),
                      ],
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
