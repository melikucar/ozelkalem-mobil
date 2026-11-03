import 'dart:async';

import 'package:flutter/material.dart';

import '../../veri/faaliyet.dart';
import '../../veri/faaliyet_deposu.dart';
import '../../veri/program.dart' show gunBasi;
import '../../veri/veri_katmani.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/cekince_esitle.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'faaliyet_ayarlari.dart';
import 'faaliyet_detay.dart';
import 'faaliyet_formu.dart';
import 'faaliyet_ortak.dart';
import 'kitapciklar_sayfasi.dart';

/// Faaliyetler: web "Faaliyetler" modülünün mobil karşılığı. Arama, kategori / yer / kaydeden / tarih süzgeçleri, aylara göre
/// gruplanmış kartlar (küçük resimli), yeni faaliyet, ayrıntı, kitapçıkları görüntüleme ve kategori-yer ayarları.
/// Yalnızca yerel veritabanını okur; değişiklikler kuyruğa yazılır.
class FaaliyetlerSayfasi extends StatefulWidget {
  const FaaliyetlerSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<FaaliyetlerSayfasi> createState() => _FaaliyetlerSayfasiState();
}

class _FaaliyetlerSayfasiState extends State<FaaliyetlerSayfasi> {
  static const _sayfa = 40;

  FaaliyetFiltre _f = const FaaliyetFiltre();
  List<Faaliyet> _liste = [];
  int _sonuc = 0;
  int _toplam = 0;
  Set<int> _sorunlu = {};
  FaaliyetReferans _ref = FaaliyetReferans({});
  bool _yuklendi = false;
  bool _sonaGeldi = false;
  bool _daha = false;

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _bekle;

  FaaliyetDeposu get _depo => widget.veri.faaliyetler;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yenile);
    _kaydirma.addListener(_kaydirildi);
    _yenile();
  }

  @override
  void dispose() {
    _depo.removeListener(_yenile);
    _kaydirma.dispose();
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
    final adet = _liste.length > _sayfa ? _liste.length : _sayfa;
    final f = _f;
    final sonuclar = await Future.wait<Object?>([
      _depo.liste(f, limit: adet),
      _depo.sonucSayisi(f),
      _depo.sayi(),
      _depo.sorunlular(),
      _depo.referans(),
    ]);
    if (!mounted || !identical(f, _f)) return;
    final liste = sonuclar[0] as List<Faaliyet>;
    setState(() {
      _liste = liste;
      _sonuc = sonuclar[1] as int;
      _toplam = sonuclar[2] as int;
      _sorunlu = (sonuclar[3] as Map<int, dynamic>).keys.toSet();
      _ref = FaaliyetReferans(sonuclar[4] as Map<String, dynamic>);
      _sonaGeldi = liste.length < adet;
      _yuklendi = true;
    });
  }

  Future<void> _dahaFazla() async {
    if (_daha || _sonaGeldi || !_yuklendi) return;
    _daha = true;
    final f = _f;
    final yeni = await _depo.liste(f, limit: _sayfa, offset: _liste.length);
    if (mounted && identical(f, _f)) {
      setState(() {
        _liste = [..._liste, ...yeni];
        _sonaGeldi = yeni.length < _sayfa;
      });
    }
    _daha = false;
  }

  void _uygula(FaaliyetFiltre f) {
    _f = f;
    _liste = [];
    _sonaGeldi = false;
    _yenile();
    if (_kaydirma.hasClients) _kaydirma.jumpTo(0);
  }

  void _araDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(
      const Duration(milliseconds: 250),
      () => _uygula(_f.kopya(kelime: v)),
    );
  }

  Future<void> _detay(Faaliyet f) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FaaliyetDetay(veri: widget.veri, yerelId: f.yerelId!),
    ),
  );

  Future<void> _yeni() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => FaaliyetFormu(veri: widget.veri)));

  Future<void> _filtrePaneli() async {
    final yeni = await showModalBottomSheet<FaaliyetFiltre>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _FiltrePaneli(f: _f, ref: _ref),
    );
    if (yeni != null) _uygula(yeni);
  }

  String get _altBaslik {
    final motor = widget.veri.motor;
    final sayi = _sonuc == _toplam
        ? '$_toplam kayıt'
        : '$_sonuc / $_toplam kayıt';
    final bekleyen = motor.kuyrukSayisi > 0
        ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek'
        : '';
    return '$sayi$bekleyen';
  }

  /// [DateTime ay başı | Faaliyet] sırası.
  List<Object> _oge() {
    final cikti = <Object>[];
    int? sonAy;
    for (final f in _liste) {
      final t = f.tarih;
      final ay = t.year * 12 + t.month;
      if (sonAy != ay) {
        cikti.add(DateTime(t.year, t.month));
        sonAy = ay;
      }
      cikti.add(f);
    }
    return cikti;
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
      floatingActionButton: KompaktDugme(
        etiket: 'Yeni faaliyet',
        onPressed: _yeni,
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.campaign_outlined,
              baslik: 'Faaliyetler',
              altBaslik: _altBaslik,
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
                      _uygula(_f.kopya(kelime: ''));
                    }
                  },
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Süzgeçler',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: _filtrePaneli,
                    ),
                    if (_f.etkin > 0)
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
                            '${_f.etkin}',
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
                        builder: (_) => v == 'kitapcik'
                            ? KitapciklarSayfasi(veri: widget.veri)
                            : FaaliyetAyarlari(veri: widget.veri),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'kitapcik',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.auto_stories_outlined),
                        title: Text('Kitapçıklar'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'ayar',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Kategori ve yerler'),
                      ),
                    ),
                  ],
                ),
              ],
              alt: (_aramaAcik || _arama.text.isNotEmpty)
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Faaliyet adı ya da içeriğinde ara',
                      degisti: _araDegisti,
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
                  stops: const [0, 0.25, 1],
                ),
              ),
              child: CekinceEsitle(motor: motor, child: _govde(tema)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _govde(ThemeData tema) {
    if (!_yuklendi) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_liste.isEmpty) {
      final suzgerli = _f.etkin > 0 || _f.kelime.trim().isNotEmpty;
      return ListView(
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
                  child: Icon(
                    suzgerli
                        ? Icons.search_off_rounded
                        : Icons.campaign_outlined,
                    size: 38,
                    color: tema.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  suzgerli
                      ? 'Kriterlere uygun faaliyet yok'
                      : 'Henüz faaliyet yok',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suzgerli ? 'Süzgeçleri ya da aramayı değiştirin.' : 'Yeni faaliyet eklemek için sağ alttaki düğmeyi kullanın.',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (suzgerli) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      _arama.clear();
                      _uygula(const FaaliyetFiltre());
                    },
                    child: const Text('Süzgeçleri temizle'),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    final ogeler = _oge();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          controller: _kaydirma,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
          itemCount: ogeler.length + (_sonaGeldi ? 0 : 1),
          itemBuilder: (c, i) {
            if (i >= ogeler.length) {
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
            final o = ogeler[i];
            if (o is DateTime) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
                child: Text(
                  '${trAylar[o.month]} ${o.year}',
                  style: tema.textTheme.labelMedium?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }
            final f = o as Faaliyet;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FaaliyetKarti(
                faaliyet: f,
                ref: _ref,
                api: widget.veri.motor.api,
                depo: _depo,
                sorunlu: _sorunlu.contains(f.yerelId),
                tikla: () => _detay(f),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FiltrePaneli extends StatefulWidget {
  const _FiltrePaneli({required this.f, required this.ref});

  final FaaliyetFiltre f;
  final FaaliyetReferans ref;

  @override
  State<_FiltrePaneli> createState() => _FiltrePaneliState();
}

class _FiltrePaneliState extends State<_FiltrePaneli> {
  late FaaliyetFiltre _f = widget.f;

  Future<void> _tarihAraligi() async {
    final simdi = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: (_f.bas != null && _f.bit != null)
          ? DateTimeRange(start: _f.bas!, end: _f.bit!)
          : DateTimeRange(start: gunBasi(simdi), end: gunBasi(simdi)),
    );
    if (r != null) setState(() => _f = _f.kopya(bas: r.start, bit: r.end));
  }

  String _gunYaz(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _secim({
    required String etiket,
    required IconData ikon,
    required int deger,
    required List<Map<String, dynamic>> liste,
    required ValueChanged<int> degisti,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<int>(
      initialValue: liste.any((x) => x['no'] == deger) ? deger : 0,
      isExpanded: true,
      decoration: InputDecoration(labelText: etiket, prefixIcon: Icon(ikon)),
      items: [
        const DropdownMenuItem(value: 0, child: Text('Hepsi')),
        for (final x in liste)
          DropdownMenuItem(value: x['no'] as int, child: Text('${x['adi']}')),
      ],
      onChanged: (v) => degisti(v ?? 0),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ref = widget.ref;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Süzgeçler', style: tema.textTheme.titleMedium),
              const SizedBox(height: 14),
              _secim(
                etiket: 'Kategori',
                ikon: Icons.category_outlined,
                deger: _f.katno,
                liste: ref.kategoriler,
                degisti: (v) => setState(() => _f = _f.kopya(katno: v)),
              ),
              _secim(
                etiket: 'Yer',
                ikon: Icons.place_outlined,
                deger: _f.yer,
                liste: ref.yerler,
                degisti: (v) => setState(() => _f = _f.kopya(yer: v)),
              ),
              _secim(
                etiket: 'Kaydeden',
                ikon: Icons.person_outline_rounded,
                deger: _f.kaydeden,
                liste: ref.kaydedenler,
                degisti: (v) => setState(() => _f = _f.kopya(kaydeden: v)),
              ),
              OutlinedButton.icon(
                onPressed: _tarihAraligi,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  _f.bas == null
                      ? 'Tarih aralığı seç'
                      : '${_gunYaz(_f.bas!)} – ${_gunYaz(_f.bit!)}',
                ),
              ),
              if (_f.bas != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _f = _f.kopya(tarihiTemizle: true)),
                    child: const Text('Tarih aralığını kaldır'),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        FaaliyetFiltre(kelime: _f.kelime),
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
