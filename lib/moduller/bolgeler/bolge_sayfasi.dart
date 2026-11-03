import 'dart:async';

import 'package:flutter/material.dart';

import '../../diger/cekince_esitle.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/bolge.dart';
import '../../veri/bolge_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../programlar/program_ortak.dart';
import '../raporlar/rapor_ortak.dart' show KpiIzgarasi, KpiVeri, sayi;
import 'bolge_detay.dart';
import 'bolge_formu.dart';
import 'bolge_ortak.dart';

/// Bölge Bilgileri: web "Bölgeler" modülünün mobil karşılığı. İlçe sekmeleri (adet rozetli), özet kutuları, arama ve köy/mahalle kartları
/// (doluluk çubuğuyla); yeni bölge, ayrıntı, düzenleme ve silme. Yalnızca yerel veritabanını okur; değişiklikler kuyruğa yazılır.
class BolgeSayfasi extends StatefulWidget {
  const BolgeSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<BolgeSayfasi> createState() => _BolgeSayfasiState();
}

class _BolgeSayfasiState extends State<BolgeSayfasi> {
  static const _sayfa = 40;

  BolgeFiltre _f = const BolgeFiltre();
  List<Bolge> _liste = [];
  int _sonuc = 0;
  List<({int ilce, String ad, int adet})> _ilceler = [];
  ({int toplam, int nufus, double doluluk}) _ozet = (
    toplam: 0,
    nufus: 0,
    doluluk: 0,
  );
  Set<int> _sorunlu = {};
  bool _yuklendi = false;
  bool _sonaGeldi = false;
  bool _daha = false;

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _bekle;

  BolgeDeposu get _depo => widget.veri.bolgeler;

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
      _depo.ilceler(),
      _depo.ozet(f),
      _depo.sorunlular(),
    ]);
    if (!mounted || !identical(f, _f)) return;
    final liste = sonuclar[0] as List<Bolge>;
    setState(() {
      _liste = liste;
      _sonuc = sonuclar[1] as int;
      _ilceler = sonuclar[2] as List<({int ilce, String ad, int adet})>;
      _ozet = sonuclar[3] as ({int toplam, int nufus, double doluluk});
      _sorunlu = (sonuclar[4] as Map<int, dynamic>).keys.toSet();
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

  void _uygula(BolgeFiltre f) {
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

  Future<void> _detay(Bolge b) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BolgeDetay(veri: widget.veri, yerelId: b.yerelId!),
    ),
  );

  Future<void> _yeni() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => BolgeFormu(veri: widget.veri)));

  String get _altBaslik {
    final motor = widget.veri.motor;
    final toplam = _ilceler.fold<int>(0, (a, b) => a + b.adet);
    final sayiMetni = _f.kelime.trim().isEmpty && _f.ilce == 0
        ? '$toplam bölge'
        : '$_sonuc / $toplam bölge';
    final bekleyen = motor.kuyrukSayisi > 0
        ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek'
        : '';
    return '$sayiMetni$bekleyen';
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
        etiket: 'Yeni bölge',
        onPressed: _yeni,
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.holiday_village_outlined,
              baslik: 'Bölge Bilgileri',
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
              ],
              alt: (_aramaAcik || _arama.text.isNotEmpty)
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Köy, mahalle, muhtar ya da bilgilerde ara',
                      degisti: _araDegisti,
                    )
                  : null,
            ),
          ),
          _ilceSekmeleri(tema),
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

  Widget _ilceSekmeleri(ThemeData tema) {
    final cs = tema.colorScheme;
    final toplam = _ilceler.fold<int>(0, (a, b) => a + b.adet);
    if (_ilceler.length < 2) return const SizedBox.shrink();
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('Tümü  $toplam'),
              selected: _f.ilce == 0,
              onSelected: (_) => _uygula(_f.kopya(ilce: 0)),
            ),
          ),
          for (final i in _ilceler)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${i.ad.isEmpty ? '—' : i.ad}  ${i.adet}'),
                selected: _f.ilce == i.ilce,
                onSelected: (_) => _uygula(_f.kopya(ilce: i.ilce)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ozetKutulari() => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: KpiIzgarasi(
      kartlar: [
        KpiVeri(
          ad: 'Bölge',
          ikon: Icons.holiday_village_outlined,
          renk: const Color(0xFF1D6FB8),
          deger: sayi(_ozet.toplam),
        ),
        KpiVeri(
          ad: 'Toplam nüfus',
          ikon: Icons.groups_2_outlined,
          renk: const Color(0xFF1F8A5B),
          deger: sayi(_ozet.nufus),
        ),
        KpiVeri(
          ad: 'Ortalama doluluk',
          ikon: Icons.donut_large_rounded,
          renk: bolgeDolulukRengi(_ozet.doluluk),
          deger: bolgeYuzde((_ozet.doluluk * 10).roundToDouble() / 10),
        ),
      ],
    ),
  );

  Widget _govde(ThemeData tema) {
    if (!_yuklendi) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_liste.isEmpty) {
      final suzgerli = _f.ilce != 0 || _f.kelime.trim().isNotEmpty;
      return ListView(
        controller: _kaydirma,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
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
                        : Icons.holiday_village_outlined,
                    size: 38,
                    color: tema.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  suzgerli ? 'Kriterlere uygun bölge yok' : 'Henüz bölge yok',
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suzgerli ? 'İlçeyi ya da aramayı değiştirin.' : 'Yeni bölge eklemek için "Yeni bölge" düğmesini kullanın.',
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
                      _uygula(const BolgeFiltre());
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          controller: _kaydirma,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
          itemCount: _liste.length + 1 + (_sonaGeldi ? 0 : 1),
          itemBuilder: (c, i) {
            if (i == 0) return _ozetKutulari();
            i -= 1;
            if (i >= _liste.length) {
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
            final b = _liste[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BolgeKarti(
                kayit: b,
                sorunlu: _sorunlu.contains(b.yerelId),
                tikla: () => _detay(b),
              ),
            );
          },
        ),
      ),
    );
  }
}
