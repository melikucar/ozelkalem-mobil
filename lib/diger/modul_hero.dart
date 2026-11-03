import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/tema.dart';
import '../veri/yazi_formatlari.dart';

/// Düğmeleri lacivert zemin üzerinde beyaz yapar.
class BeyazIkonlar extends StatelessWidget {
  const BeyazIkonlar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      iconTheme: const IconThemeData(color: Colors.white),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Colors.white),
      ),
    ),
    child: child,
  );
}

/// Modül ekranlarının ortak başlığı: ana sayfadaki gibi lacivert, yuvarlak alt köşeli, ince vurgu çizgili.
/// Başlık + alt başlık, isteğe bağlı geri oku, sağda eylemler ve altında serbest alan ([alt]: arama kutusu, filtre vb.).
class ModulHero extends StatelessWidget {
  const ModulHero({
    super.key,
    required this.baslik,
    this.altBaslik,
    this.ikon,
    this.geri = false,
    this.eylemler = const [],
    this.alt,
  });

  final String baslik;
  final String? altBaslik;
  final IconData? ikon;
  final bool geri;
  final List<Widget> eylemler;
  final Widget? alt;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ust = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(26),
          ),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Marka.lacivert, Marka.lacivert2],
          ),
          boxShadow: [
            BoxShadow(
              color: Marka.lacivert.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const HeroDokusu(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                geri ? 4 : 18,
                ust + 6,
                6,
                alt == null ? 16 : 14,
              ),
              child: BeyazIkonlar(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (geri)
                          IconButton(
                            tooltip: 'Geri',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () => Navigator.of(context).maybePop(),
                          )
                        else if (ikon != null) ...[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Icon(ikon, color: Marka.altin, size: 22),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trBuyuk(baslik),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleLarge?.copyWith(
                                  fontSize: 20,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                  height: 1.15,
                                ),
                              ),
                              if (altBaslik != null)
                                Text(
                                  altBaslik!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFC3CFDE),
                                    fontSize: 12.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (eylemler.isNotEmpty)
                          Builder(
                            builder: (c) {
                              final t = Theme.of(c);
                              return Theme(
                                data: t.copyWith(
                                  iconButtonTheme: IconButtonThemeData(
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(40, 40),
                                      padding: const EdgeInsets.all(8),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: eylemler,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    if (alt != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 12,
                          right: 12,
                          left: 0,
                        ),
                        child: alt,
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      tema.colorScheme.primary,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero içinde yarı saydam arama kutusu.
class HeroArama extends StatelessWidget {
  const HeroArama({
    super.key,
    required this.controller,
    required this.ipucu,
    required this.degisti,
  });

  final TextEditingController controller;
  final String ipucu;
  final ValueChanged<String> degisti;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFFC3CFDE),
              size: 22,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: degisti,
              textInputAction: TextInputAction.search,
              cursorColor: Marka.altin,
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              decoration: InputDecoration(
                hintText: ipucu,
                hintStyle: const TextStyle(
                  color: Color(0xFF9FB0C4),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(width: 8)
                : IconButton(
                    tooltip: 'Temizle',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFC3CFDE),
                      size: 20,
                    ),
                    onPressed: () {
                      controller.clear();
                      degisti('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Hero (başlık alanı) arka dokusu: yumuşak mavi / camgöbeği / altın ışıltılar, çapraz ince ışık şeridi ve köşede çok silik marka işareti
/// (giriş formundaki silik logo gibi). [Positioned.fill] döndürür; hero'nun [Stack]'ine ilk çocuk olarak konur.
class HeroDokusu extends StatelessWidget {
  const HeroDokusu({super.key, this.isaretBoyu = 200});

  final double isaretBoyu;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _HeroIsiltisi())),
          Positioned(
            right: -isaretBoyu * 0.16,
            bottom: -isaretBoyu * 0.26,
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/marka/isaret.png',
                width: isaretBoyu,
                height: isaretBoyu,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeroIsiltisi extends CustomPainter {
  const _HeroIsiltisi();

  void _isik(Canvas c, Offset merkez, double yaricap, Color renk, double a) {
    c.drawCircle(
      merkez,
      yaricap,
      Paint()
        ..shader = RadialGradient(
          colors: [
            renk.withValues(alpha: a),
            renk.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: merkez, radius: yaricap)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _isik(canvas, Offset(w * 0.05, h * 0.0), w * 0.55, Marka.mavi, 0.40);
    _isik(canvas, Offset(w * 0.95, h * 0.15), w * 0.42, Marka.camgobegi, 0.16);
    _isik(canvas, Offset(w * 0.55, h * 1.15), w * 0.50, Marka.mavi, 0.22);
    _isik(canvas, Offset(w * 0.02, h * 1.0), w * 0.30, Marka.altin, 0.14);
    final serit = Path()
      ..moveTo(w * 0.30, h)
      ..lineTo(w * 0.52, h)
      ..lineTo(w * 0.92, 0)
      ..lineTo(w * 0.72, 0)
      ..close();
    canvas.drawPath(
      serit,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter eski) => false;
}
