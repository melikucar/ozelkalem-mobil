import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_istemci.dart';
import '../api/oturum.dart';
import '../tema/tema.dart';
import '../diger/logo_animasyon.dart';
import '../diger/premium_alan.dart';

/// Giriş: web giriş sayfasının dili. Lacivert zemin, altın çizgili TBMM binası, beyaz marka logosu; form beyaz kartta.
/// Açılışta tek bir koreografi oynar (logo belirir, bina yükselir, form panel olarak kayar, alanlar sırayla gelir);
/// hatalı girişte form yana sallanır. "Hareketi azalt" açıksa animasyonlar atlanır.
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key, required this.oturum});

  final Oturum oturum;

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani>
    with TickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _tckn = TextEditingController();
  final _sifre = TextEditingController();
  final _sifreOdak = FocusNode();
  bool _gizli = true;
  bool _yukleniyor = false;
  String? _hata;

  late final AnimationController _acilis = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _sallan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final AnimationController _parilti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _basladi = false;

  @override
  void initState() {
    super.initState();
    _hata = widget.oturum.mesaj; // ör. "Oturumunuz sonlandırıldı"
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _acilis.value = 1;
    } else {
      _acilis.forward();
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _parilti.forward();
      });
    }
  }

  @override
  void dispose() {
    _acilis.dispose();
    _sallan.dispose();
    _parilti.dispose();
    _sifreOdak.dispose();
    _tckn.dispose();
    _sifre.dispose();
    super.dispose();
  }

  void _gizliDegistir() => setState(() => _gizli = !_gizli);

  Animation<double> _aralik(
    double b,
    double e, [
    Curve c = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _acilis,
    curve: Interval(b, e, curve: c),
  );

  Future<void> _giris() async {
    if (_yukleniyor) return;
    if (!_form.currentState!.validate()) {
      _salla();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      await widget.oturum.giris(_tckn.text.trim(), _sifre.text);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() => _hata = e.mesaj);
        _salla();
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _sifremiUnuttum() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _SifreSifirlaSayfasi(
        oturum: widget.oturum,
        baslangicTckn: _tckn.text.trim(),
      ),
    );
  }

  void _salla() {
    HapticFeedback.mediumImpact();
    if (!MediaQuery.disableAnimationsOf(context)) _sallan.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(
          0xFFE6EDF6,
        ), // panelin alt rengi: güvenli alan şeridi panelden ayrışmasın
        body: LayoutBuilder(
          builder: (context, k) {
            final yanyana =
                k.maxWidth >= 720 ||
                (k.maxWidth > k.maxHeight && k.maxWidth >= 560);
            if (yanyana) {
              return Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: _Tanitim(genis: true, acilis: _acilis),
                  ),
                  Expanded(
                    flex: 9,
                    child: _PremiumPanel(
                      yuvarlak: false,
                      child: SafeArea(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: _FormIcerik(durum: this),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            // Dar ekran: ışıltılı zeminde ortada yüzen kart (kenarlarda ve altta boşluk), üstünde logo
            return Stack(
              children: [
                Positioned.fill(
                  child: _Tanitim(
                    genis: false,
                    acilis: _acilis,
                    logoGoster: false,
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            k.maxHeight -
                            MediaQuery.paddingOf(context).vertical,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FadeTransition(
                              opacity: _aralik(0.0, 0.5),
                              child: Transform.translate(
                                offset: const Offset(-8, 0),
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimasyonluLogo(yukseklik: 84),
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            // Kart hafifçe yükselip büyüyerek belirir
                            SlideTransition(
                              position:
                                  Tween(
                                    begin: const Offset(0, 0.10),
                                    end: Offset.zero,
                                  ).animate(
                                    _aralik(0.22, 0.85, Curves.easeOutQuart),
                                  ),
                              child: ScaleTransition(
                                scale: Tween(begin: 0.94, end: 1.0).animate(
                                  _aralik(0.22, 0.85, Curves.easeOutBack),
                                ),
                                child: FadeTransition(
                                  opacity: _aralik(0.22, 0.6),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 460,
                                    ),
                                    child: _PremiumPanel(
                                      yuvarlak: true,
                                      kart: true,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          22,
                                          30,
                                          22,
                                          22,
                                        ),
                                        child: _FormIcerik(durum: this),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

/// Lacivert tanıtım alanı: beyaz marka logosu, altın çizgili bina.
class _Tanitim extends StatelessWidget {
  const _Tanitim({
    required this.genis,
    required this.acilis,
    this.logoGoster = true,
  });

  final bool genis;

  /// false: yalnız ışıltılı zemin (logo ayrıca yerleştirilir).
  final bool logoGoster;
  final Animation<double> acilis;

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.paddingOf(context).top;
    final tema = Theme.of(context).textTheme;
    // Dar alanlarda (küçük telefon, yan yana düzende dar tanıtım sütunu) logo taşmasın, genişliğe sığacak kadar küçülsün
    final logo = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: AnimasyonluLogo(yukseklik: genis ? 112 : 86),
    );
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Marka.lacivert, Marka.lacivert2],
        ),
      ),
      child: Stack(
        children: [
          // kurumsal ışıltı: mavi / camgöbeği / altın yumuşak ışık hüzmeleri
          Positioned.fill(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: acilis,
                curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
              ),
              child: const IgnorePointer(child: _Isilti()),
            ),
          ),
          if (!logoGoster)
            const SizedBox.shrink()
          else if (!genis)
            Padding(
              padding: EdgeInsets.only(
                top: ust,
                bottom: 70,
                left: 16,
                right: 16,
              ),
              child: Center(
                child: Transform.translate(
                  offset: const Offset(-10, -18),
                  child: logo,
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(40, 36 + ust, 48, 150),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  logo,
                  const SizedBox(height: 40),
                  Text(
                    'Makam çalışmaları cebinizde.',
                    style: tema.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Talepler, ajanda ve rehber; bağlantı olmasa da çalışır, bağlantı gelince kendiliğinden eşitlenir.',
                    style: tema.bodyLarge?.copyWith(
                      color: const Color(0xFFB9C6D6),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Lacivert zemin üzerinde kurumsal ışıltı: yumuşak radyal ışık hüzmeleri ve çok ince, çapraz bir ışık şeridi.
class _Isilti extends StatelessWidget {
  const _Isilti();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _IsiltiCizici());
}

class _IsiltiCizici extends CustomPainter {
  const _IsiltiCizici();

  void _isik(Canvas c, Offset merkez, double yaricap, Color renk, double a) {
    final r = Rect.fromCircle(center: merkez, radius: yaricap);
    c.drawCircle(
      merkez,
      yaricap,
      Paint()
        ..shader = RadialGradient(
          colors: [
            renk.withValues(alpha: a),
            renk.withValues(alpha: 0),
          ],
        ).createShader(r),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _isik(canvas, Offset(w * 0.12, h * 0.18), w * 0.70, Marka.mavi, 0.42);
    _isik(canvas, Offset(w * 0.92, h * 0.28), w * 0.55, Marka.camgobegi, 0.20);
    _isik(canvas, Offset(w * 0.78, h * 0.95), w * 0.60, Marka.mavi, 0.30);
    _isik(canvas, Offset(w * 0.05, h * 0.92), w * 0.42, Marka.altin, 0.20);
    // çapraz ince ışık şeridi
    final seritYol = Path()
      ..moveTo(w * 0.10, h)
      ..lineTo(w * 0.42, h)
      ..lineTo(w * 1.05, 0)
      ..lineTo(w * 0.78, 0)
      ..close();
    canvas.drawPath(
      seritYol,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // altta altın ince ışıma çizgisi
    canvas.drawRect(
      Rect.fromLTWH(0, h - 1.5, w, 1.5),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Marka.altin.withValues(alpha: 0),
            Marka.altin.withValues(alpha: 0.55),
            Marka.altin.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, h - 1.5, w, 1.5)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter eski) => false;
}

/// Bir form öğesinin alttan hafifçe yükselip belirmesi (sıralı giriş).
class _Asama extends StatelessWidget {
  const _Asama({required this.anim, required this.child});

  final Animation<double> anim;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: anim,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.18),
        end: Offset.zero,
      ).animate(anim),
      child: child,
    ),
  );
}

class _FormIcerik extends StatelessWidget {
  const _FormIcerik({required this.durum});

  final _GirisEkraniState durum;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final d = durum;
    return AnimatedBuilder(
      animation: d._sallan,
      builder: (context, child) {
        // Hatalı girişte yatay sönümlenen titreşim
        final t = d._sallan.value;
        final x = math.sin(t * math.pi * 5) * 11 * (1 - t);
        return Transform.translate(offset: Offset(x, 0), child: child);
      },
      child: AutofillGroup(
        child: Form(
          key: d._form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Asama(
                anim: d._aralik(0.40, 0.70),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SİSTEM GİRİŞİ',
                      style: tema.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF14202E),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 38,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: const LinearGradient(
                          colors: [Marka.altinKoyu, Marka.altin],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Devam etmek için bilgilerinizi giriniz.',
                      style: tema.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5B6878),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _Asama(
                anim: d._aralik(0.50, 0.80),
                child: PremiumAlan(
                  controller: d._tckn,
                  etiket: 'TCKN',
                  ikon: Icons.badge_outlined,
                  ipucu: '11 haneli TCKN',
                  etkin: !d._yukleniyor,
                  klavye: TextInputType.number,
                  eylem: TextInputAction.next,
                  otomatik: const [AutofillHints.username],
                  bicim: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  gonderildi: (_) => d._sifreOdak.requestFocus(),
                  validator: (v) => (v == null || v.length != 11)
                      ? '11 haneli TCKN girin'
                      : null,
                  sonEk: (context, metin) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: metin.length == 11
                        ? const Icon(
                            Icons.check_circle,
                            key: ValueKey('tamam'),
                            color: Color(0xFF12B76A),
                            size: 22,
                          )
                        : Text(
                            metin.isEmpty ? '' : '${metin.length}/11',
                            key: const ValueKey('sayac'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF8493A5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _Asama(
                anim: d._aralik(0.60, 0.90),
                child: PremiumAlan(
                  controller: d._sifre,
                  etiket: 'Şifre',
                  ikon: Icons.lock_outline,
                  ipucu: 'Şifreniz',
                  etkin: !d._yukleniyor,
                  gizli: d._gizli,
                  odak: d._sifreOdak,
                  eylem: TextInputAction.done,
                  otomatik: const [AutofillHints.password],
                  gonderildi: (_) => d._giris(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Şifrenizi girin' : null,
                  sonEk: (context, _) => IconButton(
                    tooltip: d._gizli ? 'Şifreyi göster' : 'Şifreyi gizle',
                    icon: Icon(
                      d._gizli
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: const Color(0xFF6B7889),
                    ),
                    onPressed: () => d._gizliDegistir(),
                  ),
                ),
              ),
              _Asama(
                anim: d._aralik(0.66, 0.95),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: d._yukleniyor ? null : () => d._sifremiUnuttum(),
                    style: TextButton.styleFrom(
                      foregroundColor: Marka.logoYazi,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text(
                      'Şifremi Unuttum',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: d._hata == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECDCA)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 20,
                                color: Color(0xFFB42318),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  d._hata!,
                                  style: const TextStyle(
                                    color: Color(0xFF7A1A12),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              _Asama(
                anim: d._aralik(0.72, 1.0),
                child: _GirisDugmesi(
                  yukleniyor: d._yukleniyor,
                  parilti: d._parilti,
                  tikla: d._giris,
                ),
              ),
              const SizedBox(height: 18),
              _Asama(
                anim: d._aralik(0.8, 1.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Color(0xFF8493A5),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Güvenli bağlantı · Sürüm ${d.widget.oturum.surum}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8493A5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lacivert gradyan düğme; açılıştan sonra üzerinden bir kez ışık süzülür (web'deki düğmeyle aynı his).
class _GirisDugmesi extends StatelessWidget {
  const _GirisDugmesi({
    required this.yukleniyor,
    required this.parilti,
    required this.tikla,
    this.etiket = 'Sisteme Giriş',
    this.ikon = Icons.login_rounded,
  });

  final bool yukleniyor;
  final Animation<double> parilti;
  final VoidCallback tikla;
  final String etiket;
  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: etiket,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B4268), Marka.lacivert],
          ),
          boxShadow: [
            BoxShadow(
              color: Marka.lacivert.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: yukleniyor ? null : tikla,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: parilti,
                      builder: (context, _) => LayoutBuilder(
                        builder: (context, k) {
                          final t = Curves.easeInOut.transform(parilti.value);
                          return Transform.translate(
                            offset: Offset(
                              -k.maxWidth * 0.5 + t * k.maxWidth * 1.7,
                              0,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Transform(
                                transform: Matrix4.skewX(-0.38),
                                child: Container(
                                  width: k.maxWidth * 0.28,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0),
                                        Colors.white.withValues(alpha: 0.22),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: yukleniyor
                        ? const SizedBox(
                            key: ValueKey('y'),
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: Marka.altin,
                            ),
                          )
                        : Row(
                            key: const ValueKey('t'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  etiket,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(ikon, color: Marka.altin, size: 22),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Form alanının zemini: gri düz renk yerine hafif gradyan, üstte altın ince çizgi, köşede silik marka işareti.
class _PremiumPanel extends StatelessWidget {
  const _PremiumPanel({
    required this.child,
    required this.yuvarlak,
    this.minYukseklik = 0,
    this.kart = false,
  });

  final Widget child;
  final bool yuvarlak;
  final double minYukseklik;

  /// true: ekranda yüzen kart (dört köşe yuvarlak, çevrede gölge ve ışıma).
  final bool kart;

  @override
  Widget build(BuildContext context) {
    final r = kart
        ? BorderRadius.circular(30)
        : yuvarlak
        ? const BorderRadius.vertical(top: Radius.circular(30))
        : BorderRadius.zero;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minYukseklik),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF1F5FA), Color(0xFFE6EDF6)],
          stops: [0, 0.55, 1],
        ),
        border: kart
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.65),
                width: 1.2,
              )
            : null,
        boxShadow: kart
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Marka.mavi.withValues(alpha: 0.28),
                  blurRadius: 60,
                  spreadRadius: -6,
                ),
              ]
            : yuvarlak
            ? [
                BoxShadow(
                  color: Marka.lacivert.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, -8),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -46,
            bottom: -34,
            child: Opacity(
              opacity: 0.06,
              child: Image.asset(
                'assets/marka/isaret.png',
                width: 250,
                height: 250,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Marka.altin.withValues(alpha: 0),
                    Marka.altinKoyu,
                    Marka.altin,
                    Marka.altinKoyu,
                    Marka.altin.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// "Şifremi unuttum": T.C. kimlik no + kayıtlı cep telefonu; eşleşirse yeni şifre SMS ile gönderilir (web ile aynı kurallar).
class _SifreSifirlaSayfasi extends StatefulWidget {
  const _SifreSifirlaSayfasi({
    required this.oturum,
    required this.baslangicTckn,
  });

  final Oturum oturum;
  final String baslangicTckn;

  @override
  State<_SifreSifirlaSayfasi> createState() => _SifreSifirlaSayfasiState();
}

class _SifreSifirlaSayfasiState extends State<_SifreSifirlaSayfasi> {
  final _form = GlobalKey<FormState>();
  late final _tckn = TextEditingController(text: widget.baslangicTckn);
  final _telefon = TextEditingController();
  final _telefonOdak = FocusNode();
  bool _yukleniyor = false;
  String? _hata;
  String? _basari;

  @override
  void dispose() {
    _tckn.dispose();
    _telefon.dispose();
    _telefonOdak.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    if (_yukleniyor || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _yukleniyor = true;
      _hata = null;
      _basari = null;
    });
    try {
      final v = await widget.oturum.api.post(
        'auth/sifre-sifirla',
        kimlik: false,
        govde: {'tckn': _tckn.text.trim(), 'telefon': _telefon.text.trim()},
      );
      final m = (v['mesaj'] ?? '').toString();
      if (mounted) {
        setState(
          () => _basari = m.isEmpty
              ? 'Bilgileriniz sistemdeki kayıtla eşleşiyorsa yeni şifreniz kayıtlı cep telefonunuza SMS ile gönderildi.'
              : m,
        );
      }
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final alt = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: alt),
      child: _PremiumPanel(
        yuvarlak: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1B4268), Marka.lacivert],
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: Marka.altin,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'ŞİFREMİ UNUTTUM',
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF14202E),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Kimlik numaranızı ve sistemde kayıtlı cep telefonunuzu girin. Bilgiler eşleşirse yeni şifreniz bağlı olduğunuz makamın SMS hesabından telefonunuza gönderilir.',
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5B6878),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                PremiumAlan(
                  controller: _tckn,
                  etiket: 'TCKN',
                  ikon: Icons.badge_outlined,
                  ipucu: '11 haneli TCKN',
                  etkin: !_yukleniyor && _basari == null,
                  klavye: TextInputType.number,
                  eylem: TextInputAction.next,
                  bicim: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  gonderildi: (_) => _telefonOdak.requestFocus(),
                  validator: (v) => (v == null || v.length != 11)
                      ? '11 haneli TCKN girin'
                      : null,
                ),
                const SizedBox(height: 16),
                PremiumAlan(
                  controller: _telefon,
                  etiket: 'Cep telefonu',
                  ikon: Icons.phone_iphone_rounded,
                  ipucu: '05XX XXX XX XX',
                  etkin: !_yukleniyor && _basari == null,
                  klavye: TextInputType.phone,
                  eylem: TextInputAction.done,
                  odak: _telefonOdak,
                  bicim: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()+-]')),
                    LengthLimitingTextInputFormatter(18),
                  ],
                  gonderildi: (_) => _gonder(),
                  validator: (v) =>
                      (v == null || v.replaceAll(RegExp(r'\D'), '').length < 10)
                      ? 'Cep telefonunuzu girin (05XX XXX XX XX)'
                      : null,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: (_hata == null && _basari == null)
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _Mesaj(
                            hata: _hata != null,
                            metin: _hata ?? _basari!,
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                _basari != null
                    ? OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Giriş ekranına dön'),
                      )
                    : _GirisDugmesi(
                        yukleniyor: _yukleniyor,
                        parilti: const AlwaysStoppedAnimation(0),
                        tikla: _gonder,
                        etiket: 'Yeni şifreyi SMS ile gönder',
                        ikon: Icons.send_rounded,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mesaj extends StatelessWidget {
  const _Mesaj({required this.hata, required this.metin});

  final bool hata;
  final String metin;

  @override
  Widget build(BuildContext context) {
    final renk = hata ? const Color(0xFFB42318) : const Color(0xFF067647);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hata ? const Color(0xFFFEF3F2) : const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hata ? const Color(0xFFFECDCA) : const Color(0xFFABEFC6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hata ? Icons.error_outline : Icons.check_circle_outline,
            size: 20,
            color: renk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(metin, style: TextStyle(color: renk, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
