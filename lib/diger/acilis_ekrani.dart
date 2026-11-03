import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Açılış ekranı: lacivert zemin, işletim sisteminin gösterdiği açılış görseliyle aynı yerde duran logo işareti
/// (geçiş kesintisiz görünür), etrafında dönen altın halka, nabız gibi atan ışıma, işaret ve yazı üzerinden geçen
/// ışık parlaması ve altta "ÖZEL KALEM OTOMASYONU" yazılı dikey logo. [animasyonlu] false ise son hâl sabit gösterilir.
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key, this.animasyonlu = true});

  final bool animasyonlu;

  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani>
    with TickerProviderStateMixin {
  late final AnimationController _giris = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _dongu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animasyonlu) {
      _giris.forward();
      _dongu.repeat();
    } else {
      _giris.value = 1;
      _dongu.value = 0.35;
    }
  }

  @override
  void dispose() {
    _giris.dispose();
    _dongu.dispose();
    super.dispose();
  }

  /// Üzerinden geçen parlama: [konum] -1.4 … 1.4 arası, bant genişliği yaklaşık %30.
  Shader _parlama(Rect r, double konum) => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: const [
      Color(0x00FFFFFF),
      Color(0x00FFFFFF),
      Color(0x99FFFFFF),
      Color(0x00FFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: const [0, 0.32, 0.5, 0.68, 1],
    transform: _Kaydir(konum),
  ).createShader(r);

  @override
  Widget build(BuildContext context) {
    final alt = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Marka.lacivert,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Marka.lacivert, Marka.lacivert2],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.14,
              child: Image.asset(
                'assets/marka/bina_altin.png',
                fit: BoxFit.fitWidth,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cy = c.maxHeight / 2 - 80;
              return AnimatedBuilder(
                animation: Listenable.merge([_giris, _dongu]),
                builder: (context, _) {
                  final g = Curves.easeOutCubic.transform(_giris.value);
                  final d = _dongu.value;
                  final yazi = Curves.easeOutCubic.transform(
                    ((_giris.value - 0.35) / 0.65).clamp(0.0, 1.0),
                  );
                  final nabiz = 0.6 + 0.2 * math.sin(2 * math.pi * d);
                  return Stack(
                    children: [
                      Positioned(
                        left: w / 2 - 200,
                        top: cy - 200,
                        width: 400,
                        height: 400,
                        child: Opacity(
                          opacity: g * nabiz,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x730060F0),
                                  Color(0x2400E0F0),
                                  Color(0x0000E0F0),
                                ],
                                stops: [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: w / 2 - 116,
                        top: cy - 116,
                        width: 232,
                        height: 232,
                        child: CustomPaint(
                          painter: _Halka(ilerleme: g, donus: d),
                        ),
                      ),
                      // Boyut ve konum, işletim sistemi açılış görseliyle aynı (288 dp, ortada): geçişte sıçrama olmaz.
                      Positioned(
                        left: w / 2 - 144,
                        top: cy - 144,
                        width: 288,
                        height: 288,
                        child: ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (r) =>
                              _parlama(r, -1.4 + 2.8 * ((d * 1.5) % 1.0)),
                          child: Image.asset(
                            'assets/ikon/acilis.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        left: w / 2 - 150,
                        top: cy + 122 + (1 - yazi) * 22,
                        width: 300,
                        child: Opacity(
                          opacity: yazi,
                          child: ShaderMask(
                            blendMode: BlendMode.srcATop,
                            shaderCallback: (r) => _parlama(
                              r,
                              -1.4 + 2.8 * (((d * 1.5) - 0.18) % 1.0),
                            ),
                            child: Image.asset(
                              'assets/marka/logo_yazi_beyaz.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 112 + alt,
            child: AnimatedBuilder(
              animation: _giris,
              builder: (context, _) => Opacity(
                opacity: _giris.value,
                child: Center(
                  child: SizedBox(
                    width: 110,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                      color: Marka.altin,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kaydir extends GradientTransform {
  const _Kaydir(this.oran);

  final double oran;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * oran, 0, 0);
}

/// Logonun etrafında önce açılan, sonra dönen altın yay; arkasında silik tam halka.
class _Halka extends CustomPainter {
  const _Halka({required this.ilerleme, required this.donus});

  final double ilerleme;
  final double donus;

  @override
  void paint(Canvas canvas, Size size) {
    final merkez = size.center(Offset.zero);
    final yaricap = size.width / 2 - 4;
    final rect = Rect.fromCircle(center: merkez, radius: yaricap);
    canvas.drawCircle(
      merkez,
      yaricap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.07 * ilerleme),
    );
    canvas.save();
    canvas.translate(merkez.dx, merkez.dy);
    canvas.rotate(2 * math.pi * donus);
    canvas.translate(-merkez.dx, -merkez.dy);
    final yay = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          Marka.altin.withValues(alpha: 0),
          Marka.altin.withValues(alpha: 0.95 * ilerleme),
        ],
        stops: const [0.0, 1.0],
        transform: const GradientRotation(0),
      ).createShader(rect);
    canvas.drawArc(rect, 0, 2 * math.pi * 0.72 * ilerleme, false, yay);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Halka eski) =>
      eski.ilerleme != ilerleme || eski.donus != donus;
}
