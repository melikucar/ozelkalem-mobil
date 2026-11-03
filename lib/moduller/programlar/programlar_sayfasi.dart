import '../../diger/kompakt_dugme.dart';
import '../../diger/cekince_esitle.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tema/tema.dart';
import '../../veri/program.dart';
import '../../veri/program_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import 'gun_cizelgesi.dart';
import 'program_detay.dart';
import 'program_formu.dart';
import 'program_ortak.dart';

enum _Gorunum { ay, hafta, gun, liste }

extension on _Gorunum {
  String get ad => switch (this) {
    _Gorunum.ay => 'Ay',
    _Gorunum.hafta => 'Hafta',
    _Gorunum.gun => 'Gün',
    _Gorunum.liste => 'Liste',
  };
}

/// Programlar: web "Program takvimi"nin mobil karşılığı. Ay / Hafta / Gün / Liste görünümleri, güne dokununca gündem,
/// gün görünümünde sürükle-bırak ile zaman değiştirme, arama, yeni program ve ayrıntı. Yalnızca yerel veritabanını okur.
class ProgramlarSayfasi extends StatefulWidget {
  const ProgramlarSayfasi({super.key, required this.veri, this.sekme = false});

  final VeriKatmani veri;
  final bool sekme;

  @override
  State<ProgramlarSayfasi> createState() => _ProgramlarSayfasiState();
}

class _ProgramlarSayfasiState extends State<ProgramlarSayfasi> {
  _Gorunum _g = _Gorunum.ay;
  late DateTime _odak = gunBasi(DateTime.now());
  List<Program> _liste = [];
  Set<int> _sorunlu = {};
  Program? _siradaki;
  int _yon = 1; // son gezinme yönü (geçiş animasyonu için)

  bool _aramaAcik = false;
  final _arama = TextEditingController();
  List<Program> _sonuc = [];
  Timer? _bekle;
  Timer? _dakika;

  ProgramDeposu get _depo => widget.veri.programlar;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yukle);
    _yukle();
    // "Şimdi" / "bitti" işaretleri ve kalan süre dakikada bir tazelenir
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

  (DateTime, DateTime) _aralik() {
    switch (_g) {
      case _Gorunum.gun:
        final g = gunBasi(_odak);
        return (g, g.add(const Duration(days: 1)));
      case _Gorunum.hafta:
        final b = haftaBasi(_odak);
        return (b, b.add(const Duration(days: 7)));
      case _Gorunum.ay:
      case _Gorunum.liste:
        final ilk = DateTime(_odak.year, _odak.month, 1);
        final son = DateTime(_odak.year, _odak.month + 1, 1);
        return (
          ilk.subtract(const Duration(days: 7)),
          son.add(const Duration(days: 8)),
        );
    }
  }

  Future<void> _yukle() async {
    final (bas, bit) = _aralik();
    final l = await _depo.aralik(bas, bit);
    final s = await _depo.sorunlular();
    final simdi = DateTime.now();
    final yaklasan = await _depo.aralik(
      simdi,
      simdi.add(const Duration(days: 30)),
    );
    Program? sonraki;
    for (final p in yaklasan) {
      if (p.bas.isAfter(simdi) &&
          (sonraki == null || p.bas.isBefore(sonraki.bas))) {
        sonraki = p;
      }
    }
    if (!mounted) return;
    setState(() {
      _liste = l;
      _sorunlu = s.keys.toSet();
      _siradaki = sonraki;
    });
  }

  void _gorunumDegistir(_Gorunum g) {
    if (g == _g) return;
    HapticFeedback.selectionClick();
    setState(() => _g = g);
    _yukle();
  }

  void _git(DateTime d, {int? yon}) {
    setState(() {
      _yon = yon ?? (d.isAfter(_odak) ? 1 : -1);
      _odak = gunBasi(d);
    });
    _yukle();
  }

  void _gezin(int adim) {
    switch (_g) {
      case _Gorunum.ay:
      case _Gorunum.liste:
        final ay = DateTime(_odak.year, _odak.month + adim, 1);
        final bugun = gunBasi(DateTime.now());
        _git(
          (ay.year == bugun.year && ay.month == bugun.month) ? bugun : ay,
          yon: adim,
        );
      case _Gorunum.hafta:
        _git(_odak.add(Duration(days: 7 * adim)), yon: adim);
      case _Gorunum.gun:
        _git(_odak.add(Duration(days: adim)), yon: adim);
    }
  }

  Future<void> _tarihSec() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _odak,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Tarihe git',
    );
    if (d != null) _git(d);
  }

  String get _baslik {
    switch (_g) {
      case _Gorunum.ay:
      case _Gorunum.liste:
        return '${trAylar[_odak.month]} ${_odak.year}';
      case _Gorunum.hafta:
        final b = haftaBasi(_odak);
        final s = b.add(const Duration(days: 6));
        return b.month == s.month
            ? '${b.day} – ${s.day} ${trAylar[s.month]} ${s.year}'
            : '${b.day} ${trAylarKisa[b.month]} – ${s.day} ${trAylarKisa[s.month]} ${s.year}';
      case _Gorunum.gun:
        return uzunGunYaz(_odak);
    }
  }

  Future<void> _ayrintiAc(Program p) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProgramDetay(veri: widget.veri, yerelId: p.yerelId!),
    ),
  );

  Future<void> _yeni([DateTime? zaman]) {
    final z = zaman ?? _varsayilanYeniZaman();
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgramFormu(veri: widget.veri, baslangic: z),
      ),
    );
  }

  /// Seçili gün bugünse sonraki tam saat, değilse 09:00.
  DateTime _varsayilanYeniZaman() {
    final n = DateTime.now();
    if (ayniGun(_odak, n)) {
      final s = n.hour + 1;
      return DateTime(n.year, n.month, n.day, s > 23 ? 23 : s);
    }
    return DateTime(_odak.year, _odak.month, _odak.day, 9);
  }

  void _araDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(const Duration(milliseconds: 250), () async {
      final r = await _depo.ara(v);
      if (mounted) setState(() => _sonuc = r);
    });
  }

  List<Program> _gununProgramlari(DateTime gun) =>
      _liste.where((p) => programGundeMi(p, gun)).toList();

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
      floatingActionButton: _g == _Gorunum.gun || _aramaAcik
          ? null
          : KompaktDugme(etiket: 'Yeni program', onPressed: () => _yeni()),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: motor,
            builder: (context, _) => ModulHero(
              geri: !widget.sekme,
              ikon: Icons.event_outlined,
              baslik: 'Programlar',
              altBaslik: _aramaAcik
                  ? 'Programlarda ara'
                  : '$_baslik${motor.kuyrukSayisi > 0 ? ' · ${motor.kuyrukSayisi} değişiklik gönderilecek' : ''}',
              eylemler: [
                IconButton(
                  tooltip: _aramaAcik ? 'Aramayı kapat' : 'Ara',
                  icon: Icon(
                    _aramaAcik ? Icons.close_rounded : Icons.search_rounded,
                  ),
                  onPressed: () => setState(() {
                    _aramaAcik = !_aramaAcik;
                    if (!_aramaAcik) {
                      _arama.clear();
                      _sonuc = [];
                    }
                  }),
                ),
              ],
              alt: _aramaAcik
                  ? HeroArama(
                      controller: _arama,
                      ipucu: 'Program adı ya da yer ara',
                      degisti: _araDegisti,
                    )
                  : _GorunumSecici(secili: _g, sec: _gorunumDegistir),
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
                child: _aramaAcik ? _aramaSonuclari() : _govde(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aramaSonuclari() {
    if (_arama.text.trim().isEmpty) {
      return _Bos(
        ikon: Icons.manage_search_rounded,
        baslik: 'Program ara',
        alt: 'Ad ya da yer yazın; sonuçlar yeniden eskiye sıralanır.',
      );
    }
    if (_sonuc.isEmpty) {
      return const _Bos(
        ikon: Icons.search_off_rounded,
        baslik: 'Program bulunamadı',
        alt: 'Başka bir kelime deneyin.',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
      itemCount: _sonuc.length,
      itemBuilder: (c, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ProgramKarti(
          program: _sonuc[i],
          gun: gunBasi(_sonuc[i].bas),
          tarihGoster: true,
          sorunlu: _sorunlu.contains(_sonuc[i].yerelId),
          tikla: () => _ayrintiAc(_sonuc[i]),
        ),
      ),
    );
  }

  Widget _govde() {
    final navigasyon = _Navigasyon(
      baslik: _baslik,
      bugundeMi: ayniGun(_odak, DateTime.now()),
      onceki: () => _gezin(-1),
      sonraki: () => _gezin(1),
      baslikTikla: _tarihSec,
      bugun: () => _git(gunBasi(DateTime.now())),
    );
    final govde = switch (_g) {
      _Gorunum.ay => _ayGorunumu(),
      _Gorunum.hafta => _haftaGorunumu(),
      _Gorunum.gun => GunCizelgesi(
        key: const ValueKey('gun'),
        gun: _odak,
        programlar: _gununProgramlari(_odak),
        depo: _depo,
        ac: _ayrintiAc,
        yeni: _yeni,
        sorunlu: _sorunlu,
      ),
      _Gorunum.liste => _listeGorunumu(),
    };
    final kaydirmali = _g != _Gorunum.gun;
    return Column(
      children: [
        navigasyon,
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 350) _gezin(v < 0 ? 1 : -1);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(0.08 * _yon, 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: c,
                ),
              ),
              layoutBuilder: (cur, onc) => Stack(children: [...onc, ?cur]),
              child: KeyedSubtree(
                key: ValueKey(
                  '$_g-${_odak.year}-${_odak.month}-${_g == _Gorunum.ay || _g == _Gorunum.liste ? 0 : _odak.day}',
                ),
                child: kaydirmali ? govde : govde,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ AY

  Widget _ayGorunumu() {
    final secilenProgramlar = _gununProgramlari(_odak);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_siradaki != null)
          SliverToBoxAdapter(
            child: _SiradakiSerit(
              program: _siradaki!,
              tikla: () => _ayrintiAc(_siradaki!),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: _AyIzgarasi(
              ay: DateTime(_odak.year, _odak.month, 1),
              secili: _odak,
              programlar: _liste,
              sec: (d) {
                HapticFeedback.selectionClick();
                if (d.month != _odak.month) {
                  _git(d);
                } else {
                  setState(() => _odak = d);
                }
              },
              yeni: (d) {
                HapticFeedback.mediumImpact();
                _yeni(DateTime(d.year, d.month, d.day, 9));
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _GundemBasligi(
            gun: _odak,
            adet: secilenProgramlar.length,
            ekle: () => _yeni(),
          ),
        ),
        _gundemSliver(secilenProgramlar, _odak),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  Widget _gundemSliver(List<Program> l, DateTime gun) {
    if (l.isEmpty) {
      return SliverToBoxAdapter(
        child: _Bos(
          ikon: Icons.event_available_outlined,
          baslik: 'Bu gün için program yok',
          alt: 'Yeni program eklemek için aşağıdaki düğmeyi kullanın.',
          kucuk: true,
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList.builder(
        itemCount: l.length,
        itemBuilder: (c, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ProgramKarti(
            program: l[i],
            gun: gun,
            sorunlu: _sorunlu.contains(l[i].yerelId),
            tikla: () => _ayrintiAc(l[i]),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ HAFTA

  Widget _haftaGorunumu() {
    final b = haftaBasi(_odak);
    final gunler = [for (var i = 0; i < 7; i++) b.add(Duration(days: i))];
    final bugun = gunBasi(DateTime.now());
    final satirlar = <Widget>[];
    for (final g in gunler) {
      final l = _gununProgramlari(g);
      satirlar.add(
        InkWell(
          onTap: () => setState(() => _odak = g),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Text(
                  '${ayniGun(g, bugun) ? 'Bugün · ' : ''}${gunBaslikYaz(g)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ayniGun(g, bugun)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                if (l.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${l.length}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Bu güne program ekle',
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  onPressed: () => _yeni(DateTime(g.year, g.month, g.day, 9)),
                ),
              ],
            ),
          ),
        ),
      );
      if (l.isEmpty) {
        satirlar.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
            child: Text(
              'Program yok',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      } else {
        for (final p in l) {
          satirlar.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ProgramKarti(
                program: p,
                gun: g,
                sorunlu: _sorunlu.contains(p.yerelId),
                tikla: () => _ayrintiAc(p),
              ),
            ),
          );
        }
      }
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _HaftaSeridi(
            gunler: gunler,
            secili: _odak,
            programlar: _liste,
            sec: (d) {
              HapticFeedback.selectionClick();
              setState(() {
                _odak = gunBasi(d);
                _g = _Gorunum.gun;
              });
              _yukle();
            },
          ),
        ),
        if (_siradaki != null)
          SliverToBoxAdapter(
            child: _SiradakiSerit(
              program: _siradaki!,
              tikla: () => _ayrintiAc(_siradaki!),
            ),
          ),
        SliverList(delegate: SliverChildListDelegate(satirlar)),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  // ------------------------------------------------------------------ LİSTE

  Widget _listeGorunumu() {
    final ilk = DateTime(_odak.year, _odak.month, 1);
    final son = DateTime(_odak.year, _odak.month + 1, 1);
    final ayProgramlari = _liste
        .where((p) => !p.bas.isBefore(ilk) && p.bas.isBefore(son))
        .toList();
    if (ayProgramlari.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          _Bos(
            ikon: Icons.event_busy_outlined,
            baslik: 'Bu ay program yok',
            alt: 'Başka bir aya geçin ya da yeni program ekleyin.',
          ),
        ],
      );
    }
    final ogeler = <Widget>[];
    DateTime? sonGun;
    final bugun = gunBasi(DateTime.now());
    for (final p in ayProgramlari) {
      final g = gunBasi(p.bas);
      if (sonGun == null || !ayniGun(g, sonGun)) {
        sonGun = g;
        ogeler.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(
              '${ayniGun(g, bugun) ? 'Bugün · ' : ''}${gunBaslikYaz(g)}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: ayniGun(g, bugun)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      ogeler.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: ProgramKarti(
            program: p,
            gun: g,
            sorunlu: _sorunlu.contains(p.yerelId),
            tikla: () => _ayrintiAc(p),
          ),
        ),
      );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_siradaki != null)
          SliverToBoxAdapter(
            child: _SiradakiSerit(
              program: _siradaki!,
              tikla: () => _ayrintiAc(_siradaki!),
            ),
          ),
        SliverList(delegate: SliverChildListDelegate(ogeler)),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }
}

// ====================================================================== parçalar

/// Hero içindeki görünüm seçici: Ay / Hafta / Gün / Liste. Seçili hap yaylanarak kayar.
class _GorunumSecici extends StatelessWidget {
  const _GorunumSecici({required this.secili, required this.sec});

  final _Gorunum secili;
  final ValueChanged<_Gorunum> sec;

  @override
  Widget build(BuildContext context) {
    const liste = _Gorunum.values;
    return Container(
      height: 40,
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
                  for (final g in liste)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => sec(g),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: g == secili
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: g == secili
                                  ? Marka.lacivert
                                  : Colors.white,
                            ),
                            child: Text(g.ad),
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

/// Önceki / sonraki, başlık (dokununca tarihe git) ve "Bugün" kısayolu.
class _Navigasyon extends StatelessWidget {
  const _Navigasyon({
    required this.baslik,
    required this.bugundeMi,
    required this.onceki,
    required this.sonraki,
    required this.baslikTikla,
    required this.bugun,
  });

  final String baslik;
  final bool bugundeMi;
  final VoidCallback onceki;
  final VoidCallback sonraki;
  final VoidCallback baslikTikla;
  final VoidCallback bugun;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Önceki',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onceki,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: baslikTikla,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        baslik,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!bugundeMi)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: bugun,
              child: const Text('Bugün'),
            ),
          IconButton(
            tooltip: 'Sonraki',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: sonraki,
          ),
        ],
      ),
    );
  }
}

/// Sıradaki yaklaşan program: tek satır, vurgu rengiyle.
class _SiradakiSerit extends StatelessWidget {
  const _SiradakiSerit({required this.program, required this.tikla});

  final Program program;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final renk = program.renk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Material(
        color: renk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: tikla,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: renk),
                const SizedBox(width: 8),
                Text(
                  'Sıradaki',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: renk,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    program.adi,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  kalanYazi(program),
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ay ızgarası: 6 satır × 7 gün; her günde en çok 3 renk noktası, dokununca seçilir, uzun basınca o güne program ekler.
class _AyIzgarasi extends StatelessWidget {
  const _AyIzgarasi({
    required this.ay,
    required this.secili,
    required this.programlar,
    required this.sec,
    required this.yeni,
  });

  final DateTime ay;
  final DateTime secili;
  final List<Program> programlar;
  final ValueChanged<DateTime> sec;
  final ValueChanged<DateTime> yeni;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final bugun = gunBasi(DateTime.now());
    final ilk = DateTime(ay.year, ay.month, 1);
    final baslangic = ilk.subtract(Duration(days: ilk.weekday - 1));
    final gunSayisi = DateTime(ay.year, ay.month + 1, 0).day;
    final satir = ((ilk.weekday - 1 + gunSayisi) / 7).ceil();

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: programGolgesi(context),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 1; i <= 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      trGunlerKisa[i],
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: i >= 6
                            ? cs.error.withValues(alpha: 0.8)
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var r = 0; r < satir; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _Hucre(
                      gun: baslangic.add(Duration(days: r * 7 + c)),
                      buAy: ay.month,
                      bugun: bugun,
                      secili: secili,
                      programlar: programlar,
                      sec: sec,
                      yeni: yeni,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Hucre extends StatelessWidget {
  const _Hucre({
    required this.gun,
    required this.buAy,
    required this.bugun,
    required this.secili,
    required this.programlar,
    required this.sec,
    required this.yeni,
  });

  final DateTime gun;
  final int buAy;
  final DateTime bugun;
  final DateTime secili;
  final List<Program> programlar;
  final ValueChanged<DateTime> sec;
  final ValueChanged<DateTime> yeni;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buAyda = gun.month == buAy;
    final bugunMu = ayniGun(gun, bugun);
    final seciliMi = ayniGun(gun, secili);
    final l = programlar.where((p) => programGundeMi(p, gun)).toList();
    final vurgu = cs.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => sec(gun),
      onLongPress: () => yeni(gun),
      child: SizedBox(
        height: 50,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 42,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: seciliMi
                  ? vurgu
                  : bugunMu
                  ? vurgu.withValues(alpha: 0.12)
                  : null,
              border: bugunMu && !seciliMi
                  ? Border.all(color: vurgu, width: 1.2)
                  : null,
              boxShadow: seciliMi
                  ? [
                      BoxShadow(
                        color: vurgu.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${gun.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: (bugunMu || seciliMi || l.isNotEmpty)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: seciliMi
                        ? cs.onPrimary
                        : buAyda
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.32),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in l.take(3))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1.2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: seciliMi ? cs.onPrimary : p.renk,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GundemBasligi extends StatelessWidget {
  const _GundemBasligi({
    required this.gun,
    required this.adet,
    required this.ekle,
  });

  final DateTime gun;
  final int adet;
  final VoidCallback ekle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final bugun = ayniGun(gun, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${bugun ? 'Bugün · ' : ''}${gunBaslikYaz(gun)}',
              style: tema.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: tema.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              adet == 0 ? 'Program yok' : '$adet program',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tema.colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bu güne program ekle',
            icon: const Icon(Icons.add_circle_rounded),
            color: tema.colorScheme.primary,
            onPressed: ekle,
          ),
        ],
      ),
    );
  }
}

/// Hafta görünümünün üst şeridi: 7 gün, gün adı + numarası + program noktaları. Dokununca o günün zaman çizelgesi açılır.
class _HaftaSeridi extends StatelessWidget {
  const _HaftaSeridi({
    required this.gunler,
    required this.secili,
    required this.programlar,
    required this.sec,
  });

  final List<DateTime> gunler;
  final DateTime secili;
  final List<Program> programlar;
  final ValueChanged<DateTime> sec;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bugun = gunBasi(DateTime.now());
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: programGolgesi(context),
      ),
      child: Row(
        children: [
          for (final g in gunler)
            Expanded(
              child: GestureDetector(
                onTap: () => sec(g),
                child: Builder(
                  builder: (context) {
                    final l = programlar
                        .where((p) => programGundeMi(p, g))
                        .toList();
                    final bugunMu = ayniGun(g, bugun);
                    final seciliMi = ayniGun(g, secili);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: seciliMi
                            ? cs.primary
                            : bugunMu
                            ? cs.primary.withValues(alpha: 0.12)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            trGunlerKisa[g.weekday],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: seciliMi
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${g.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: seciliMi ? cs.onPrimary : cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 6,
                            child: l.isEmpty
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final p in l.take(3))
                                        Container(
                                          width: 5,
                                          height: 5,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: seciliMi
                                                ? cs.onPrimary
                                                : p.renk,
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bos extends StatelessWidget {
  const _Bos({
    required this.ikon,
    required this.baslik,
    required this.alt,
    this.kucuk = false,
  });

  final IconData ikon;
  final String baslik;
  final String alt;
  final bool kucuk;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(40, kucuk ? 12 : 60, 40, kucuk ? 12 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: kucuk ? 56 : 80,
            height: kucuk ? 56 : 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tema.colorScheme.primary.withValues(alpha: 0.10),
            ),
            child: Icon(
              ikon,
              size: kucuk ? 28 : 38,
              color: tema.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            baslik,
            textAlign: TextAlign.center,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            alt,
            textAlign: TextAlign.center,
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gündem/liste kartı: renk şeridi, zaman, ad, yer, durum rozetleri (şimdi / bitti / sıradaki), hatırlatıcı ve eşitleme simgeleri.
class ProgramKarti extends StatelessWidget {
  const ProgramKarti({
    super.key,
    required this.program,
    required this.gun,
    required this.tikla,
    this.sorunlu = false,
    this.tarihGoster = false,
  });

  final Program program;
  final DateTime gun;
  final VoidCallback tikla;
  final bool sorunlu;

  /// Arama sonuçlarında tarih de yazılır.
  final bool tarihGoster;

  (String, String) _zaman() {
    final p = program;
    if (tarihGoster) {
      return (
        '${p.bas.day} ${trAylarKisa[p.bas.month]}',
        p.tumGun ? 'Gün boyu' : saatYaz(p.bas),
      );
    }
    if (p.tumGun) return ('Gün', 'boyu');
    final g = gunBasi(gun);
    final sonG = g.add(const Duration(days: 1));
    final basBuGunde = !p.bas.isBefore(g);
    final bitBuGunde = !p.bit.isAfter(sonG);
    if (basBuGunde && bitBuGunde) return (saatYaz(p.bas), saatYaz(p.bit));
    if (basBuGunde) return (saatYaz(p.bas), '→');
    if (bitBuGunde) return ('→', saatYaz(p.bit));
    return ('Gün', 'boyu');
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final p = program;
    final renk = p.renk;
    final durum = programZamaniDurumu(p);
    final (ust, alt) = _zaman();
    final hat = p.hatirlatici;
    final kalan =
        durum == ProgramZamani.gelecek && ayniGun(p.bas, DateTime.now())
        ? kalanYazi(p)
        : '';

    Widget rozet(String yazi, Color r, {IconData? ikon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: r.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[
            Icon(ikon, size: 12, color: r),
            const SizedBox(width: 4),
          ],
          Text(
            yazi,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: r,
            ),
          ),
        ],
      ),
    );

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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: renk),
                Container(
                  width: 60,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ust,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: renk,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alt,
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Opacity(
                    opacity: durum == ProgramZamani.gecmis ? 0.62 : 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 11, 12, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.adi,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          if (p.yer.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    p.yer,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          Builder(
                            builder: (context) {
                              final r = <Widget>[
                                if (durum == ProgramZamani.suan && !p.tumGun)
                                  rozet(
                                    'ŞİMDİ',
                                    const Color(0xFF12A150),
                                    ikon: Icons.circle,
                                  ),
                                if (durum == ProgramZamani.gecmis)
                                  rozet('Bitti', cs.outline),
                                if (kalan.isNotEmpty)
                                  rozet(
                                    kalan,
                                    renk,
                                    ikon: Icons.schedule_rounded,
                                  ),
                                if (hat != null && !hat.bos)
                                  rozet(
                                    '${hat.dakikalar.length}',
                                    cs.onSurfaceVariant,
                                    ikon: Icons.notifications_none_rounded,
                                  ),
                                if (p.randevuNo > 0)
                                  rozet(
                                    'Randevu',
                                    const Color(0xFF636E82),
                                    ikon: Icons.handshake_outlined,
                                  ),
                                if (sorunlu)
                                  rozet(
                                    'Çakışma',
                                    Colors.amber.shade800,
                                    ikon: Icons.warning_amber_rounded,
                                  )
                                else if (p.bekleyen)
                                  rozet(
                                    'Gönderilecek',
                                    cs.outline,
                                    ikon: Icons.cloud_upload_outlined,
                                  ),
                              ];
                              if (r.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 5,
                                  children: r,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
