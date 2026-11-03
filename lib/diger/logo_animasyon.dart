import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Giriş ekranının marka logosu. Elmas halka işareti döne döne yerine oturur, arkasında camgöbeği bir ışıma nefes alır;
/// "ÖZEL KALEM OTOMASYONU" yazısı soldan sağa açılarak belirir. Sonrasında birkaç saniyede bir logonun üzerinden ışık süzülür.
/// "Hareketi azalt" açıksa hareketsiz, tam görünümde durur.
class AnimasyonluLogo extends StatefulWidget {
  const AnimasyonluLogo({super.key, this.yukseklik = 78, this.yaziOlcek = 1.0});

  /// İşaretin yüksekliği; yazı buna göre ölçeklenir.
  final double yukseklik;

  /// Yazı kısmının ek büyütme oranı (işaret aynı kalır).
  final double yaziOlcek;

  @override
  State<AnimasyonluLogo> createState() => _AnimasyonluLogoState();
}

class _AnimasyonluLogoState extends State<AnimasyonluLogo>
    with TickerProviderStateMixin {
  late final AnimationController _giris = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  late final AnimationController _dongu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6000),
  );
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _giris.value = 1;
    } else {
      _giris.forward().then((_) {
        if (mounted) _dongu.repeat();
      });
    }
  }

  @override
  void dispose() {
    _giris.dispose();
    _dongu.dispose();
    super.dispose();
  }

  Animation<double> _a(double b, double e, Curve c) => CurvedAnimation(
    parent: _giris,
    curve: Interval(b, e, curve: c),
  );

  @override
  Widget build(BuildContext context) {
    final yuk = widget.yukseklik;
    final isaretGenislik = yuk * (331 / 321);
    // Yazı görselinde görünen kısım yüksekliğin %74'ü (üstte boşluk var): görünen yazı bloğu işaretle AYNI yükseklikte olacak şekilde
    // büyütülür; sonra görünen kısmın ortası işaretin ortasına denk gelsin diye yukarı kaydırılır (üst-üste, alt-alta hizalı).
    final yaziYuk = yuk * (255 / 189) * widget.yaziOlcek;
    final yaziKayma = -yaziYuk * 0.1176;
    final yaziGenislik = yaziYuk * (530 / 255);

    final isaretDonus = _a(0.0, 0.62, Curves.easeOutBack);
    final isaretGorun = _a(0.0, 0.30, Curves.easeOut);
    final isik = _a(0.05, 0.55, Curves.easeOut);
    final yaziAc = _a(0.38, 0.88, Curves.easeOutCubic);

    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // İşaret + ışıma
        SizedBox(
          width: isaretGenislik,
          height: yuk,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([isik, _dongu]),
                builder: (context, _) {
                  final nefes =
                      0.5 + 0.5 * math.sin(_dongu.value * 2 * math.pi);
                  final boy =
                      yuk * (1.7 + 0.18 * nefes) * (0.5 + 0.5 * isik.value);
                  return Opacity(
                    opacity: (0.55 + 0.35 * nefes) * isik.value,
                    child: Container(
                      width: boy,
                      height: boy,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Marka.camgobegi.withValues(alpha: 0.45),
                            Marka.mavi.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),
              FadeTransition(
                opacity: isaretGorun,
                child: AnimatedBuilder(
                  animation: isaretDonus,
                  builder: (context, child) => Transform.rotate(
                    angle: (1 - isaretDonus.value) * -math.pi * 0.75,
                    child: Transform.scale(
                      scale: 0.45 + 0.55 * isaretDonus.value,
                      child: child,
                    ),
                  ),
                  child: Image.asset(
                    'assets/marka/logo_isaret.png',
                    height: yuk,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: yuk * 0.16),
        // Yazı: soldan sağa açılır
        AnimatedBuilder(
          animation: yaziAc,
          builder: (context, child) => ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: yaziAc.value.clamp(0.0, 1.0),
              child: Opacity(
                opacity: yaziAc.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(-14 * (1 - yaziAc.value), 0),
                  child: child,
                ),
              ),
            ),
          ),
          child: Transform.translate(
            offset: Offset(0, yaziKayma),
            child: Image.asset(
              'assets/marka/logo_yazi_beyaz.png',
              width: yaziGenislik,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ],
    );

    // Işık süzülmesi: döngünün ilk %26'sında köşegen bir parlama logonun üzerinden geçer
    return AnimatedBuilder(
      animation: _dongu,
      child: logo,
      builder: (context, child) {
        final t = (_dongu.value / 0.26).clamp(0.0, 1.0);
        final etkin = _dongu.isAnimating && _dongu.value < 0.26;
        if (!etkin) return child!;
        final x = -0.6 + 2.2 * Curves.easeInOut.transform(t);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(x - 0.35, -0.6),
            end: Alignment(x + 0.35, 0.6),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.75),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}
