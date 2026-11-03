import 'dart:async';

import 'package:flutter/material.dart';

import '../../veri/program.dart' show gunBasi, ayniGun;
import '../../veri/randevu.dart';
import '../../veri/randevu_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/cekince_esitle.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'randevu_detay.dart';
import 'randevu_formu.dart';
import 'randevu_ortak.dart';

/// Randevular: web "Randevular" modülünün mobil karşılığı. Yaklaşan / Bugün / Geçmiş / Tümü sekmeleri (sayaçlarla),
/// kategori çipleri, durum – kaydeden – tarih aralığı süzgeçleri, arama, hızlı durum değiştirme, yeni randevu ve ayrıntı.
/// Yalnızca yerel veritabanını okur; değişiklikler kuyruğa yazılır.
class RandevularSayfasi extends StatefulWidget {
  const RandevularSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<RandevularSayfasi> createState() => _RandevularSayfasiState();
}

class _RandevularSayfasiState extends State<RandevularSayfasi> {
  RandevuFiltre _f = const RandevuFiltre();
  List<Randevu> _liste = [];
  Map<RandevuZaman, int> _sayilar = {};
  Set<int> _sorunlu = {};
  RandevuReferans _ref = RandevuReferans({});
  bool _yuklendi = false;

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  Timer? _bekle;
  Timer? _dakika;

  RandevuDeposu get _depo => widget.veri.randevular;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yukle);
    _yukle();
    // "Bugün / Yarın" etiketleri gece yarısını geçince de doğru kalsın
    _dakika = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _depo.removeListener(_yukle);
    _bekle?.cancel();
    _dakika?.cancel();
    _arama.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final sonuclar = await Future.wait<Object?>([
      _depo.liste(_f),
      _depo.zamanSayilari(),
      _depo.sorunlular(),
      _depo.referans(),
    ]);
    if (!mounted) return;
    setState(() {
      _liste = sonuclar[0] as List<Randevu>;
      _sayilar = sonuclar[1] as Map<RandevuZaman, int>;
      _sorunlu = (sonuclar[2] as Map<int, dynamic>).keys.toSet();
      _ref = RandevuReferans(sonuclar[3] as Map<String, dynamic>);
      _yuklendi = true;
    });
  }

  void _filtreDegistir(RandevuFiltre f) {
    _f = f;
    _yukle();
  }

  void _araDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(
      const Duration(milliseconds: 250),
      () => _filtreDegistir(_f.kopya(kelime: v)),
    );
  }

  Future<void> _detay(Randevu r) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RandevuDetay(veri: widget.veri, yerelId: r.yerelId!),
    ),
  );

  Future<void> _yeni() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RandevuFormu(veri: widget.veri)));

  // ------------------------------------------------------------------ süzgeç paneli

  Future<void> _filtrePaneli() async {
    final yeni = await showModalBottomSheet<RandevuFiltre>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _FiltrePaneli(f: _f, ref: _ref),
    );
    if (yeni != null) _filtreDegistir(yeni);
  }

  String get _altBaslik {
    final n = _liste.length;
    final motor = widget.veri.motor;
    final bekleyen = motor.kuyrukSayisi > 0
        ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek'
        : '';
    if (_aramaAcik) return 'Randevularda ara';
    return '$n randevu$bekleyen';
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
        etiket: 'Yeni randevu',
        onPressed: _yeni,
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.event_available_outlined,
              baslik: 'Randevular',
              altBaslik: _altBaslik,
              eylemler: [
                IconButton(
                  tooltip: _aramaAcik ? 'Aramayı kapat' : 'Ara',
                  icon: Icon(
                    _aramaAcik ? Icons.close_rounded : Icons.search_rounded,
                  ),
                  onPressed: () {
                    setState(() => _aramaAcik = !_aramaAcik);
                    if (!_aramaAcik) {
                      _arama.clear();
                      _filtreDegistir(_f.kopya(kelime: ''));
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
              ],
              alt: _aramaAcik
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Ad, ünvan, telefon, yer ya da not ara',
                      degisti: _araDegisti,
                    )
                  : ZamanSecici(
                      secili: _f.zaman,
                      sayilar: _sayilar,
                      sec: (z) => _filtreDegistir(_f.kopya(zaman: z)),
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
              child: Column(
                children: [
                  Expanded(
                    child: CekinceEsitle(motor: motor, child: _govde(tema)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Satırları güne göre gruplar: [DateTime gün | Randevu].
  List<Object> _oge() {
    final cikti = <Object>[];
    DateTime? son;
    for (final r in _liste) {
      final g = gunBasi(r.bas);
      if (son == null || !ayniGun(son, g)) {
        cikti.add(g);
        son = g;
      }
      cikti.add(r);
    }
    return cikti;
  }

  String _gunBasligi(DateTime g) {
    final fark = g.difference(gunBasi(DateTime.now())).inDays;
    final ek = switch (fark) {
      0 => 'Bugün · ',
      1 => 'Yarın · ',
      -1 => 'Dün · ',
      _ => '',
    };
    return '$ek${g.day} ${trAylar[g.month]} ${g.year} ${trGunler[g.weekday]}';
  }

  Widget _govde(ThemeData tema) {
    if (!_yuklendi) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_liste.isEmpty) {
      final suzgerli = _f.etkin > 0 || _f.kelime.trim().isNotEmpty;
      return ListView(
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
                        : Icons.event_busy_outlined,
                    size: 38,
                    color: tema.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  suzgerli
                      ? 'Kriterlere uygun randevu yok'
                      : 'Bu sekmede randevu yok',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suzgerli ? 'Süzgeçleri ya da aramayı değiştirin.' : 'Yeni randevu eklemek için sağ alttaki düğmeyi kullanın.',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_f.zaman != RandevuZaman.tumu) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        _filtreDegistir(_f.kopya(zaman: RandevuZaman.tumu)),
                    child: const Text('Tüm randevuları göster'),
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
        constraints: const BoxConstraints(maxWidth: 1400),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
          itemCount: ogeler.length,
          itemBuilder: (c, i) {
            final o = ogeler[i];
            if (o is DateTime) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
                child: Text(
                  _gunBasligi(o),
                  style: tema.textTheme.labelMedium?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }
            final r = o as Randevu;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RandevuKarti(
                randevu: r,
                ref: _ref,
                sorunlu: _sorunlu.contains(r.yerelId),
                tikla: () => _detay(r),
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

  final RandevuFiltre f;
  final RandevuReferans ref;

  @override
  State<_FiltrePaneli> createState() => _FiltrePaneliState();
}

class _FiltrePaneliState extends State<_FiltrePaneli> {
  late RandevuFiltre _f = widget.f;

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
              if (ref.kategoriler.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  initialValue: _f.katno,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Hepsi')),
                    for (final k in ref.kategoriler)
                      DropdownMenuItem(
                        value: k['no'] as int,
                        child: Text('${k['adi']}'),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _f = _f.kopya(katno: v ?? 0)),
                ),
                const SizedBox(height: 14),
              ],
              DropdownButtonFormField<int>(
                initialValue: _f.durum,
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
                            color: ref.durumRengi(d['no'] as int),
                          ),
                          const SizedBox(width: 10),
                          Text('${d['adi']}'),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _f = _f.kopya(durum: v ?? 0)),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _f.kaydeden,
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
                        RandevuFiltre(zaman: _f.zaman, kelime: _f.kelime),
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
