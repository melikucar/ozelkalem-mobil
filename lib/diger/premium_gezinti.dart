import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Alttaki gezintide bir sayfa (sekme).
class GezintiOgesi {
  const GezintiOgesi(this.ad, this.ikon, this.seciliIkon);

  final String ad;
  final IconData ikon;
  final IconData seciliIkon;
}

/// Gezintide sayfa değiştirmeyen eylem (bildirimler, profil…). Dokununca [tikla] çalışır.
/// [kaynak]: düğmenin ekran dikdörtgeni (yukarı açılan menüler buna göre hizalanır).
class GezintiEylemi {
  const GezintiEylemi({
    required this.ad,
    required this.ikon,
    required this.tikla,
    this.ozel,
  });

  final String ad;
  final IconData ikon;
  final void Function(Rect kaynak) tikla;

  /// Simge yerine gösterilecek özel çizim (ör. profil fotoğrafı). Boyut 30 × 30.
  final Widget Function(BuildContext context)? ozel;
}

/// Premium alt gezinti: zeminsiz, eğimli bir tasarım. Ortada yuvarlak, ışımalı "Modüller" düğmesi; tepesinden sağa ve sola doğru
/// akıcı bir çizgi aşağı iner ve bittiği uçlarda solda ana sayfa, sağda profil düğmeleri durur.
/// "Modüller" düğmesi baloncuklar açar: tüm modüller ve [panelEylemleri] (bildirimler) yüzen baloncuklar hâlinde çıkar.
/// Ana sayfa ve profil seçili gösterilmez; yalnız ortadaki Modüller düğmesi vurgulu durur.
class PremiumGezinti extends StatefulWidget {
  const PremiumGezinti({
    super.key,
    required this.ogeler,
    required this.secili,
    required this.sec,
    required this.stil,
    this.eylemler = const [],
    this.panelEylemleri = const [],
  });

  /// Sayfalar; 0. öğe ana sayfadır (solda), diğerleri "Modüller" baloncuklarında listelenir.
  final List<GezintiOgesi> ogeler;
  final int secili;
  final ValueChanged<int> sec;
  final String stil; // klasik | kurumsal | cam (çizgi parlaklığını etkiler)

  /// Sağ uçtaki eylem düğmesi (profil).
  final List<GezintiEylemi> eylemler;

  /// "Modüller" baloncuklarında modüllerle birlikte çıkan eylemler (bildirimler…).
  final List<GezintiEylemi> panelEylemleri;

  static const yukseklik = 76.0;
  static const _orta = 64.0; // merkez düğme çapı
  static const _uc = 46.0; // uç düğme çapı

  @override
  State<PremiumGezinti> createState() => _PremiumGezintiState();
}

class _PremiumGezintiState extends State<PremiumGezinti> {
  final _ortaAnahtar = GlobalKey();

  Rect _kaynak(BuildContext c) {
    final kutu = c.findRenderObject() as RenderBox;
    return kutu.localToGlobal(Offset.zero) & kutu.size;
  }

  Future<void> _baloncuklariAc() {
    final dugme = _kaynak(_ortaAnahtar.currentContext!);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black.withValues(alpha: 0.30),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (c, anim, _) => _Baloncuklar(
        dugme: dugme,
        ogeler: widget.ogeler,
        eylemler: widget.panelEylemleri,
        secili: widget.secili,
        animasyon: anim,
        sec: (i) {
          Navigator.of(c).pop();
          widget.sec(i);
        },
        eylem: (e) {
          Navigator.of(c).pop();
          e.tikla(dugme);
        },
      ),
      transitionBuilder: (c, anim, _, child) => BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 7 * anim.value,
          sigmaY: 7 * anim.value,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final v = cs.primary;
    final alt = MediaQuery.paddingOf(context).bottom;

    final profil = widget.eylemler.isEmpty ? null : widget.eylemler.first;
    return Padding(
      padding: EdgeInsets.only(bottom: alt > 0 ? alt : 6),
      child: SizedBox(
        height: PremiumGezinti.yukseklik,
        child: LayoutBuilder(
          builder: (context, k) {
            final w = k.maxWidth;
            const yan = 30.0;
            const ucY = 38.0; // uç düğmelerin merkez yüksekliği
            const ortaY = ucY; // merkez düğmenin merkez yüksekliği
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // sol uç: ana sayfa. Zaten ana sayfadayken gizlenir (yumuşakça küçülüp kaybolur, dokunulamaz)
                Positioned(
                  left: yan,
                  top: ucY - PremiumGezinti._uc / 2,
                  child: IgnorePointer(
                    ignoring: widget.secili == 0,
                    child: ExcludeSemantics(
                      excluding: widget.secili == 0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        scale: widget.secili == 0 ? 0.0 : 1.0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: widget.secili == 0 ? 0.0 : 1.0,
                          child: _UcDugme(
                            ikon: Icon(widget.ogeler[0].ikon),
                            ad: widget.ogeler[0].ad,
                            tikla: (_) {
                              HapticFeedback.selectionClick();
                              widget.sec(0);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // sağ uç: profil
                if (profil != null)
                  Positioned(
                    right: yan,
                    top: ucY - PremiumGezinti._uc / 2,
                    child: IgnorePointer(
                      ignoring: widget.secili == 0,
                      child: ExcludeSemantics(
                        excluding: widget.secili == 0,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          scale: widget.secili == 0 ? 0.0 : 1.0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: widget.secili == 0 ? 0.0 : 1.0,
                            child: _UcDugme(
                              ikon: profil.ozel != null
                                  ? profil.ozel!(context)
                                  : Icon(profil.ikon),
                              ad: profil.ad,
                              tikla: (kaynak) {
                                HapticFeedback.selectionClick();
                                profil.tikla(kaynak);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // merkez: Modüller
                Positioned(
                  left: (w - PremiumGezinti._orta) / 2,
                  top: ortaY - PremiumGezinti._orta / 2,
                  child: _OrtaDugme(
                    key: _ortaAnahtar,
                    vurgu: v,
                    tikla: () {
                      HapticFeedback.mediumImpact();
                      _baloncuklariAc();
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Modüller düğmesinin içindeki baloncuklar: sudaki baloncuklar gibi sürekli, hafifçe yüzer ve esner (yukarı-aşağı salınır,
/// yuvarlaklıkları nefes alır gibi yassılıp uzar). Döngü kesintisizdir; "hareketi azalt" açıksa sabit durur.
class _SuBaloncuklari extends StatefulWidget {
  const _SuBaloncuklari({super.key, required this.renk});

  final Color renk;

  @override
  State<_SuBaloncuklari> createState() => _SuBaloncuklariState();
}

class _SuBaloncuklariState extends State<_SuBaloncuklari>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (!MediaQuery.disableAnimationsOf(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(34, 34),
      painter: _SuBaloncukCizici(_c, widget.renk),
    ),
  );
}

class _SuBaloncukCizici extends CustomPainter {
  _SuBaloncukCizici(this.anim, this.renk) : super(repaint: anim);

  final Animation<double> anim;
  final Color renk;

  // (merkez x, merkez y, yarıçap, faz, yatay salınım, dikey salınım) — boyuta oranla
  static const _b = [
    (0.60, 0.56, 0.205, 0.00, 0.045, 0.075),
    (0.25, 0.68, 0.135, 0.31, 0.050, 0.085),
    (0.36, 0.24, 0.100, 0.62, 0.055, 0.070),
    (0.80, 0.22, 0.062, 0.87, 0.040, 0.060),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final s = size.width;
    for (final (cx, cy, r, faz, ax, ay) in _b) {
      final x = (cx + ax * math.sin(2 * math.pi * (t + faz))) * s;
      // dikey salınım yatay olandan farklı hızda: bir 8 çizer gibi akar
      final y = (cy + ay * math.sin(2 * math.pi * (2 * t + faz * 1.7))) * s;
      // esneme: bir eksen uzarken diğeri kısalır (alan korunur)
      final e = 0.11 * math.sin(2 * math.pi * (3 * t + faz));
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(1 + e, 1 - e);
      final rr = r * s;
      canvas.drawCircle(
        Offset.zero,
        rr,
        Paint()..color = renk.withValues(alpha: 0.96),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SuBaloncukCizici eski) => eski.renk != renk;
}

/// Merkez "Modüller" düğmesi: yuvarlak, vurgu renginde gradyanlı ve ışımalı; yavaşça "nefes alır".
class _OrtaDugme extends StatefulWidget {
  const _OrtaDugme({super.key, required this.vurgu, required this.tikla});

  final Color vurgu;
  final VoidCallback tikla;

  @override
  State<_OrtaDugme> createState() => _OrtaDugmeState();
}

class _OrtaDugmeState extends State<_OrtaDugme> {
  bool _basili = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = widget.vurgu;
    return Semantics(
      button: true,
      selected: true,
      label: 'Modüller',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _basili = true),
        onTapCancel: () => setState(() => _basili = false),
        onTapUp: (_) => setState(() => _basili = false),
        onTap: widget.tikla,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          scale: _basili ? 0.9 : 1,
          child: Container(
            width: PremiumGezinti._orta,
            height: PremiumGezinti._orta,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(v, Colors.white, 0.22)!,
                  Color.lerp(v, Colors.black, 0.30)!,
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: v.withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // üstte parıltı
                Positioned(
                  top: 3,
                  child: Container(
                    width: 36,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.38),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                _SuBaloncuklari(
                  key: const ValueKey('modul_dugme_simge'),
                  renk: cs.onPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Çizginin uçlarındaki küçük yuvarlak düğme (ana sayfa, profil): ince ışımalı halka içinde yalnız simge.
class _UcDugme extends StatefulWidget {
  const _UcDugme({required this.ikon, required this.ad, required this.tikla});

  final Widget ikon;
  final String ad;
  final void Function(Rect kaynak) tikla;

  @override
  State<_UcDugme> createState() => _UcDugmeState();
}

class _UcDugmeState extends State<_UcDugme> {
  bool _basili = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = cs.primary;
    return Semantics(
      button: true,
      label: widget.ad,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _basili = true),
        onTapCancel: () => setState(() => _basili = false),
        onTapUp: (_) => setState(() => _basili = false),
        onTap: () {
          final kutu = context.findRenderObject() as RenderBox;
          widget.tikla(kutu.localToGlobal(Offset.zero) & kutu.size);
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: _basili ? 0.88 : 1,
          child: Container(
            width: PremiumGezinti._uc,
            height: PremiumGezinti._uc,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surface.withValues(alpha: 0.94),
              border: Border.all(color: v.withValues(alpha: 0.55), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: v.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: IconTheme(
              data: IconThemeData(color: cs.onSurface, size: 24),
              child: widget.ikon,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Modüller" baloncukları: düğmenin üstünde, aşağıdan yukarı genişleyen bir salkım. Her baloncuk düğmeden fırlar, sonra yavaşça
/// süzülür. Seçili modül vurgu renginde dolu görünür. Karttan arındırılmış: zemin yok, yalnız yüzen baloncuklar.
class _Baloncuklar extends StatefulWidget {
  const _Baloncuklar({
    required this.dugme,
    required this.ogeler,
    required this.eylemler,
    required this.secili,
    required this.animasyon,
    required this.sec,
    required this.eylem,
  });

  final Rect dugme;
  final List<GezintiOgesi> ogeler;
  final List<GezintiEylemi> eylemler;
  final int secili;
  final Animation<double> animasyon;
  final ValueChanged<int> sec;
  final ValueChanged<GezintiEylemi> eylem;

  @override
  State<_Baloncuklar> createState() => _BaloncuklarState();
}

class _BaloncuklarState extends State<_Baloncuklar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _suzul = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    _suzul.repeat();
  }

  @override
  void dispose() {
    _suzul.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ekran = MediaQuery.sizeOf(context);
    final sayfalar = [for (var i = 1; i < widget.ogeler.length; i++) i];
    final toplam = sayfalar.length + widget.eylemler.length;
    final genislik = (ekran.width - 56) / 2;
    final hapler = <Widget>[];
    for (var n = 0; n < toplam; n++) {
      final sayfaMi = n < sayfalar.length;
      final gi = sayfaMi ? sayfalar[n] : -1;
      final e = sayfaMi ? null : widget.eylemler[n - sayfalar.length];
      hapler.add(
        _Hap(
          genislik: genislik,
          ikon: sayfaMi
              ? (gi == widget.secili
                    ? widget.ogeler[gi].seciliIkon
                    : widget.ogeler[gi].ikon)
              : e!.ikon,
          ad: sayfaMi ? widget.ogeler[gi].ad : e!.ad,
          secili: sayfaMi && gi == widget.secili,
          sira: n,
          animasyon: widget.animasyon,
          suzul: _suzul,
          tikla: () {
            HapticFeedback.selectionClick();
            if (sayfaMi) {
              widget.sec(gi);
            } else {
              widget.eylem(e!);
            }
          },
        ),
      );
    }
    // iki sütun; çift satırlar hafif kaydırılır (organik, dalgalı dizilim)
    final satirlar = <Widget>[];
    for (var i = 0; i < hapler.length; i += 2) {
      final cift = hapler.skip(i).take(2).toList();
      satirlar.add(
        Padding(
          padding: EdgeInsets.only(
            left: (i ~/ 2).isOdd ? 22 : 0,
            right: (i ~/ 2).isOdd ? 0 : 22,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: cift,
          ),
        ),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: ekran.height - widget.dugme.top + 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: satirlar.reversed.toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek bir pill (hap) düğme: solda simge yuvası, sağda ad. Seçili olan vurgu renginde dolu görünür.
class _Hap extends StatelessWidget {
  const _Hap({
    required this.genislik,
    required this.ikon,
    required this.ad,
    required this.secili,
    required this.sira,
    required this.animasyon,
    required this.suzul,
    required this.tikla,
  });

  final double genislik;
  final IconData ikon;
  final String ad;
  final bool secili;
  final int sira;
  final Animation<double> animasyon;
  final Animation<double> suzul;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = cs.primary;
    final giris = CurvedAnimation(
      parent: animasyon,
      curve: Interval(
        (sira * 0.05).clamp(0.0, 0.55),
        1,
        curve: Curves.easeOutBack,
      ),
    );
    final faz = sira * 0.37;
    final onYuz = secili ? cs.onPrimary : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: AnimatedBuilder(
        animation: Listenable.merge([giris, suzul]),
        builder: (context, _) {
          final t = giris.value.clamp(0.0, 1.4);
          final dy = math.sin((suzul.value + faz) * 2 * math.pi) * 2.5;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, dy + (1 - t) * 40),
              child: Transform.scale(scale: t, child: _govde(cs, v, onYuz)),
            ),
          );
        },
      ),
    );
  }

  Widget _govde(ColorScheme cs, Color v, Color onYuz) {
    return GestureDetector(
      onTap: tikla,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: genislik,
        height: 48,
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: secili
              ? LinearGradient(
                  colors: [
                    Color.lerp(v, Colors.white, 0.18)!,
                    Color.lerp(v, Colors.black, 0.25)!,
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.surface, Color.lerp(cs.surface, v, 0.12)!],
                ),
          border: Border.all(
            color: secili
                ? Colors.white.withValues(alpha: 0.55)
                : v.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: v.withValues(alpha: secili ? 0.5 : 0.25),
              blurRadius: secili ? 20 : 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: secili
                      ? [
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0.12),
                        ]
                      : [
                          Color.lerp(v, Colors.white, 0.25)!,
                          Color.lerp(v, Colors.black, 0.2)!,
                        ],
                ),
              ),
              child: Icon(ikon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                  letterSpacing: 0.1,
                  color: onYuz,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sekme sayfaları arasında geçiş: tüm sayfalar canlı kalır (durum korunur); seçilen sayfa kısa bir solma + yukarı kayma
/// ile belirir. "Hareketi azalt" açıksa geçiş animasyonsuzdur.
class GecisliSayfalar extends StatefulWidget {
  const GecisliSayfalar({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<GecisliSayfalar> createState() => _GecisliSayfalarState();
}

class _GecisliSayfalarState extends State<GecisliSayfalar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  );

  @override
  void didUpdateWidget(GecisliSayfalar eski) {
    super.didUpdateWidget(eski);
    if (eski.index != widget.index &&
        !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final egri = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween(begin: 0.0, end: 1.0).animate(egri),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(egri),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
