import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/oturum.dart';
import '../../diger/cekince_esitle.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/veri_katmani.dart';
import '../../veri/yazisma.dart';
import '../../veri/yazisma_deposu.dart';
import '../programlar/program_ortak.dart';
import 'yazisma_detay.dart';
import 'yazisma_formu.dart';
import 'yazisma_ortak.dart';
import 'yazisma_sablonlari.dart';

/// Yazışmalar: web "Yazışmalar" modülünün mobil karşılığı. Arama, dönem / kaydeden / kişi süzgeçleri, aylara göre gruplanmış kartlar,
/// yeni yazı (şablonlu), ayrıntı (A4 önizleme, PDF / Word, WhatsApp / e-posta) ve şablon yönetimi.
/// Yalnızca yerel veritabanını okur; değişiklikler kuyruğa yazılır.
class YazismalarSayfasi extends StatefulWidget {
  const YazismalarSayfasi({
    super.key,
    required this.veri,
    required this.oturum,
    this.sekme = false,
  });

  final VeriKatmani veri;
  final Oturum oturum;
  final bool sekme;

  @override
  State<YazismalarSayfasi> createState() => _YazismalarSayfasiState();
}

class _YazismalarSayfasiState extends State<YazismalarSayfasi> {
  static const _sayfa = 40;

  YazismaFiltre _f = const YazismaFiltre();
  List<Yazisma> _liste = [];
  int _sonuc = 0;
  int _toplam = 0;
  Set<int> _sorunlu = {};
  YazismaReferans _ref = YazismaReferans({});
  bool _yuklendi = false;
  bool _sonaGeldi = false;
  bool _daha = false;

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _bekle;

  YazismaDeposu get _depo => widget.veri.yazismalar;

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
    final liste = sonuclar[0] as List<Yazisma>;
    setState(() {
      _liste = liste;
      _sonuc = sonuclar[1] as int;
      _toplam = sonuclar[2] as int;
      _sorunlu = (sonuclar[3] as Map<int, dynamic>).keys.toSet();
      _ref = YazismaReferans(sonuclar[4] as Map<String, dynamic>);
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

  void _uygula(YazismaFiltre f) {
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

  Future<void> _detay(Yazisma y) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => YazismaDetay(
        veri: widget.veri,
        oturum: widget.oturum,
        yerelId: y.yerelId!,
      ),
    ),
  );

  Future<void> _yeni() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => YazismaFormu(veri: widget.veri, oturum: widget.oturum),
    ),
  );

  Future<void> _filtrePaneli() async {
    final kisiler = await _depo.enCokYazilanlar();
    if (!mounted) return;
    final yeni = await showModalBottomSheet<YazismaFiltre>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _FiltrePaneli(f: _f, ref: _ref, kisiler: kisiler),
    );
    if (yeni != null) _uygula(yeni);
  }

  String get _altBaslik {
    final motor = widget.veri.motor;
    final sayi = _sonuc == _toplam
        ? '$_toplam yazı'
        : '$_sonuc / $_toplam yazı';
    final bekleyen = motor.kuyrukSayisi > 0
        ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek'
        : '';
    return '$sayi$bekleyen';
  }

  /// [DateTime ay başı | Yazisma] sırası.
  List<Object> _oge() {
    final cikti = <Object>[];
    int? sonAy;
    for (final y in _liste) {
      final t = y.tarih;
      final ay = t.year * 12 + t.month;
      if (sonAy != ay) {
        cikti.add(DateTime(t.year, t.month));
        sonAy = ay;
      }
      cikti.add(y);
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
      floatingActionButton: KompaktDugme(etiket: 'Yeni yazı', onPressed: _yeni),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.mail_outline_rounded,
              baslik: 'Yazışmalar',
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
                        builder: (_) => YazismaSablonlari(veri: widget.veri),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'sablon',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.description_outlined),
                        title: Text('Yazı şablonları'),
                      ),
                    ),
                  ],
                ),
              ],
              alt: (_aramaAcik || _arama.text.isNotEmpty)
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Muhatap, ünvan ya da metinde ara',
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
                        : Icons.mail_outline_rounded,
                    size: 38,
                    color: tema.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  suzgerli ? 'Kriterlere uygun yazı yok' : 'Henüz yazı yok',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suzgerli ? 'Süzgeçleri ya da aramayı değiştirin.' : 'Yeni yazı hazırlamak için sağ alttaki düğmeyi kullanın.',
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
                      _uygula(const YazismaFiltre());
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
            final y = o as Yazisma;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: YazismaKarti(
                yazisma: y,
                kaydeden: _ref.kaydedenAdi(y.ekleyen),
                sorunlu: _sorunlu.contains(y.yerelId),
                tikla: () => _detay(y),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FiltrePaneli extends StatefulWidget {
  const _FiltrePaneli({
    required this.f,
    required this.ref,
    required this.kisiler,
  });

  final YazismaFiltre f;
  final YazismaReferans ref;
  final List<({String kisi, int adet})> kisiler;

  @override
  State<_FiltrePaneli> createState() => _FiltrePaneliState();
}

class _FiltrePaneliState extends State<_FiltrePaneli> {
  late YazismaFiltre _f = widget.f;

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
              Text('Dönem', style: tema.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final d in YazismaDonem.values)
                    ChoiceChip(
                      label: Text(d.etiket),
                      selected: _f.donem == d,
                      onSelected: (_) =>
                          setState(() => _f = _f.kopya(donem: d)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: ref.kaydedenler.any((k) => k.no == _f.kaydeden)
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
                    DropdownMenuItem(value: k.no, child: Text(k.adi)),
                ],
                onChanged: (v) =>
                    setState(() => _f = _f.kopya(kaydeden: v ?? 0)),
              ),
              if (widget.kisiler.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'En çok yazı yazılan kişiler',
                  style: tema.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final k in widget.kisiler)
                      FilterChip(
                        label: Text('${k.kisi} (${k.adet})'),
                        selected: _f.kisi == k.kisi,
                        onSelected: (s) => setState(
                          () => _f = _f.kopya(kisi: s ? k.kisi : ''),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        YazismaFiltre(kelime: _f.kelime),
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
