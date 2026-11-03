import 'dart:async';

import 'package:flutter/material.dart';

import '../../diger/cekince_esitle.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/tbmm.dart';
import '../../veri/tbmm_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../programlar/program_ortak.dart';
import '../raporlar/rapor_ortak.dart' show KpiIzgarasi, KpiVeri, sayi;
import 'tbmm_detay.dart';
import 'tbmm_formu.dart';
import 'tbmm_ortak.dart';

/// TBMM: web "TBMM" modülünün mobil karşılığı. Kanun teklifi ve önerge türleri sekmeleri (adet rozetli), tür özeti, arama,
/// aylara göre gruplanmış kartlar, yeni kayıt, ayrıntı (ek dosyalar, PDF) ve listeyi PDF olarak yazdırma.
/// Yalnızca yerel veritabanını okur; değişiklikler kuyruğa yazılır.
class TbmmSayfasi extends StatefulWidget {
  const TbmmSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<TbmmSayfasi> createState() => _TbmmSayfasiState();
}

class _TbmmSayfasiState extends State<TbmmSayfasi> {
  static const _sayfa = 40;

  TbmmFiltre _f = const TbmmFiltre();
  List<Tbmm> _liste = [];
  int _sonuc = 0;
  Map<int, int> _turSayilari = {};
  ({int toplam, int buAy, int buYil, String? son}) _ozet = (
    toplam: 0,
    buAy: 0,
    buYil: 0,
    son: null,
  );
  Set<int> _sorunlu = {};
  TbmmReferans _ref = TbmmReferans({});
  bool _yuklendi = false;
  bool _sonaGeldi = false;
  bool _daha = false;
  bool _pdf = false;

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  final _kaydirma = ScrollController();
  Timer? _bekle;

  TbmmDeposu get _depo => widget.veri.tbmm;

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
      _depo.turSayilari(),
      _depo.ozet(f.tablo),
      _depo.sorunlular(),
      _depo.referans(),
    ]);
    if (!mounted || !identical(f, _f)) return;
    final liste = sonuclar[0] as List<Tbmm>;
    setState(() {
      _liste = liste;
      _sonuc = sonuclar[1] as int;
      _turSayilari = sonuclar[2] as Map<int, int>;
      _ozet = sonuclar[3] as ({int toplam, int buAy, int buYil, String? son});
      _sorunlu = (sonuclar[4] as Map<int, dynamic>).keys.toSet();
      _ref = TbmmReferans(sonuclar[5] as Map<String, dynamic>);
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

  void _uygula(TbmmFiltre f) {
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

  Future<void> _detay(Tbmm t) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TbmmDetay(veri: widget.veri, yerelId: t.yerelId!),
    ),
  );

  Future<void> _yeni() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TbmmFormu(veri: widget.veri, baslangicTuru: _f.tablo),
    ),
  );

  Future<void> _listeyiYazdir() async {
    if (_f.tablo == 0) {
      _mesaj('Listeyi yazdırmak için önce bir tür seçin.');
      return;
    }
    setState(() => _pdf = true);
    final q = Uri(
      queryParameters: {
        'tablo': '${_f.tablo}',
        if (_f.kelime.trim().isNotEmpty) 'kelime': _f.kelime.trim(),
      },
    ).query;
    final h = await tbmmPdfAc(
      widget.veri.motor.api,
      'tbmm/pdf?$q',
      'tbmm-liste.pdf',
    );
    if (mounted) {
      setState(() => _pdf = false);
      if (h != null) _mesaj(h);
    }
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  String get _altBaslik {
    final motor = widget.veri.motor;
    final toplam = _turSayilari.values.fold<int>(0, (a, b) => a + b);
    final sayiMetni = _f.kelime.trim().isEmpty && _f.tablo == 0
        ? '$toplam kayıt'
        : '$_sonuc / $toplam kayıt';
    final bekleyen = motor.kuyrukSayisi > 0
        ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek'
        : '';
    return '$sayiMetni$bekleyen';
  }

  /// [DateTime ay başı | Tbmm] sırası.
  List<Object> _oge() {
    final cikti = <Object>[];
    int? sonAy;
    for (final t in _liste) {
      final d = t.tarih;
      final ay = d.year * 12 + d.month;
      if (sonAy != ay) {
        cikti.add(DateTime(d.year, d.month));
        sonAy = ay;
      }
      cikti.add(t);
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
    final turAdi = _f.tablo == 0 ? 'kayıt' : _ref.tabloAdi(_f.tablo);
    return Scaffold(
      floatingActionButtonLocation: widget.sekme
          ? const BarUstuKonum()
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: KompaktDugme(
        etiket: _f.tablo == 0 ? 'Yeni kayıt' : 'Yeni ${turAdi.toLowerCase()}',
        onPressed: _yeni,
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.account_balance_outlined,
              baslik: 'TBMM',
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
                if (_pdf)
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
                  PopupMenuButton<String>(
                    padding: const EdgeInsets.all(8),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == 'yazdir') _listeyiYazdir();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'yazdir',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.print_outlined),
                          title: Text('Listeyi yazdır (PDF)'),
                        ),
                      ),
                    ],
                  ),
              ],
              alt: (_aramaAcik || _arama.text.isNotEmpty)
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Ad, içerik ya da notlarda ara',
                      degisti: _araDegisti,
                    )
                  : null,
            ),
          ),
          _turSekmeleri(tema),
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

  Widget _turSekmeleri(ThemeData tema) {
    final cs = tema.colorScheme;
    final toplam = _turSayilari.values.fold<int>(0, (a, b) => a + b);
    final turler = _ref.tablolar;
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
              selected: _f.tablo == 0,
              onSelected: (_) => _uygula(_f.kopya(tablo: 0)),
            ),
          ),
          for (final t in turler)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: Icon(
                  tbmmIkonu((t['no'] as num).toInt()),
                  size: 16,
                  color: tbmmRengi((t['no'] as num).toInt()),
                ),
                label: Text(
                  '${t['adi']}  ${_turSayilari[(t['no'] as num).toInt()] ?? 0}',
                ),
                selected: _f.tablo == (t['no'] as num).toInt(),
                onSelected: (_) =>
                    _uygula(_f.kopya(tablo: (t['no'] as num).toInt())),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ozetKutulari() {
    final son = _ozet.son == null
        ? '–'
        : tbmmTarihKisa(DateTime.tryParse(_ozet.son!) ?? DateTime.now());
    final ad = _f.tablo == 0 ? 'kayıt' : _ref.tabloAdi(_f.tablo).toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: KpiIzgarasi(
        kartlar: [
          KpiVeri(
            ad: 'Toplam $ad',
            ikon: _f.tablo == 0
                ? Icons.account_balance_outlined
                : tbmmIkonu(_f.tablo),
            renk: const Color(0xFFB91C1C),
            deger: sayi(_ozet.toplam),
          ),
          KpiVeri(
            ad: 'Bu ay',
            ikon: Icons.calendar_today_outlined,
            renk: const Color(0xFF1D6FB8),
            deger: sayi(_ozet.buAy),
          ),
          KpiVeri(
            ad: 'Bu yıl',
            ikon: Icons.event_available_outlined,
            renk: const Color(0xFF1F8A5B),
            deger: sayi(_ozet.buYil),
          ),
          KpiVeri(
            ad: 'Son kayıt',
            ikon: Icons.history_rounded,
            renk: const Color(0xFF7C3AED),
            deger: son,
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
      final suzgerli = _f.tablo != 0 || _f.kelime.trim().isNotEmpty;
      return ListView(
        controller: _kaydirma,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
        children: [
          _ozetKutulari(),
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
                        : Icons.account_balance_outlined,
                    size: 38,
                    color: tema.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  suzgerli ? 'Kriterlere uygun kayıt yok' : 'Henüz kayıt yok',
                  textAlign: TextAlign.center,
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suzgerli
                      ? 'Türü ya da aramayı değiştirin.'
                      : 'Yeni kayıt eklemek için sağ alttaki düğmeyi kullanın.',
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
                      _uygula(const TbmmFiltre());
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
          itemCount: ogeler.length + 1 + (_sonaGeldi ? 0 : 1),
          itemBuilder: (c, i) {
            if (i == 0) return _ozetKutulari();
            i -= 1;
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
                padding: const EdgeInsets.fromLTRB(4, 10, 0, 8),
                child: Text(
                  '${trAylar[o.month]} ${o.year}',
                  style: tema.textTheme.labelMedium?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }
            final t = o as Tbmm;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TbmmKarti(
                kayit: t,
                turAdi: _ref.tabloAdi(t.tablo),
                kaydeden: _ref.kaydedenAdi(t.ekleyen),
                sorunlu: _sorunlu.contains(t.yerelId),
                tikla: () => _detay(t),
              ),
            );
          },
        ),
      ),
    );
  }
}
