import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../senkron/senkron_motoru.dart';

/// Liste sayfasını en üstteyken hafifçe aşağı çekince: içerik parmağın ardından (yaylanarak) biraz aşağı iner, hafif bir titreşim gelir,
/// yeterince çekilince eşitleme başlar (başlıktaki yükleniyor simgesi hemen döner) ve bırakınca içerik yerine yaylanır.
/// Sayfa kaydırılabilir olmasa bile çekme algılansın diye alttaki kaydırma alanı `AlwaysScrollableScrollPhysics` kullanmalıdır.
class CekinceEsitle extends StatefulWidget {
  const CekinceEsitle({super.key, required this.motor, required this.child});

  final SenkronMotoru motor;
  final Widget child;

  @override
  State<CekinceEsitle> createState() => _CekinceEsitleState();
}

/// Çekme miktarını (ham piksel) ekranda görünen kaymaya çevirir: önce kolay, sonra giderek zorlaşan "lastik" hissi; en çok ~46 px.
double cekmeKaymasi(double ham) => 46 * (1 - math.exp(-ham / 60));

/// İçeriği [kayma] kadar aşağı indirir; çekilirken parmağı izler, bırakılınca yaylanarak yerine döner.
class CekmeKaydirici extends StatelessWidget {
  const CekmeKaydirici({super.key, required this.kayma, required this.child});

  final double kayma;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: kayma),
    duration: Duration(milliseconds: kayma == 0 ? 420 : 70),
    curve: kayma == 0 ? Curves.easeOutBack : Curves.linear,
    builder: (c, d, ch) => Transform.translate(offset: Offset(0, d), child: ch),
    child: child,
  );
}

/// Eşitleme başlarken cihazda kısa, hafif titreşim (sistem dokunma geri bildirimi kapalı olsa da çalışır).
Future<void> titret() async {
  try {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 45, amplitude: 120);
    }
  } catch (_) {}
}

/// Aşağı çekince içeriğin üstünde (hero'nun altında) açılan eşitleme göstergesi: çekerken "Eşitlemek için çekin", sürerken dönen simge,
/// bitince "Tüm veriler sistemle eşitlendi (N kayıt)" ya da "Çevrimdışı". [kayma]: içeriğin o anki aşağı inişi (görünürlüğü belirler).
class EsitlemeGostergesi extends StatelessWidget {
  const EsitlemeGostergesi({
    super.key,
    required this.durum,
    required this.kayma,
    required this.bitisMetni,
  });

  final EsitlemeDurumu durum;
  final double kayma;
  final String bitisMetni;

  /// Eşitleme sürerken içeriğin açık tutulduğu mesafe (gösterge bu boşlukta durur).
  static const yukseklik = 44.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Widget ikon;
    final String metin;
    switch (durum) {
      case EsitlemeDurumu.esitleniyor:
        ikon = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: cs.primary),
        );
        metin = 'Eşitleniyor…';
      case EsitlemeDurumu.tamam:
        ikon = Icon(Icons.check_circle_rounded, size: 18, color: cs.primary);
        metin = bitisMetni;
      case EsitlemeDurumu.cevrimdisi:
        ikon = Icon(Icons.cloud_off_rounded, size: 18, color: cs.error);
        metin = 'Çevrimdışı';
      case EsitlemeDurumu.bos:
        ikon = Transform.rotate(
          angle: kayma / 46 * math.pi,
          child: Icon(Icons.sync_rounded, size: 18, color: cs.primary),
        );
        metin = 'Eşitlemek için çekin';
    }
    return Opacity(
      opacity: (kayma / 30).clamp(0.0, 1.0),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: yukseklik,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ikon,
              const SizedBox(width: 8),
              Text(
                metin,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum EsitlemeDurumu { bos, esitleniyor, tamam, cevrimdisi }

/// 12345 → "12.345" (kayıt sayısı gösterimi).
String binlik(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]}.',
);

/// Eşitleme bitince gösterilen ortak mesaj; [n] cihazdaki toplam kayıt sayısı.
String esitlendiMetni(int? n) => n == null
    ? 'Tüm veriler sistemle eşitlendi'
    : 'Tüm veriler sistemle eşitlendi (${binlik(n)} kayıt)';

class _CekinceEsitleState extends State<CekinceEsitle> {
  /// Eşitlemeyi tetiklemek için gereken çekme miktarı (mantıksal piksel): hafif bir çekiş yeter.
  static const _esik = 36.0;

  /// Eşitleme sürerken içeriğin açık tutulduğu mesafe (gösterge bu boşlukta durur).
  static const _tutma = 44.0;

  final ValueNotifier<double> _kayma = ValueNotifier(0);
  double _asiri = 0;
  bool _tetiklendi = false;
  EsitlemeDurumu _durum = EsitlemeDurumu.bos;
  String _bitisMetni = 'Tüm veriler sistemle eşitlendi';

  @override
  void dispose() {
    _kayma.dispose();
    super.dispose();
  }

  Future<void> _esitle() async {
    setState(() => _durum = EsitlemeDurumu.esitleniyor);
    _kayma.value = _tutma;
    try {
      await widget.motor.elleSenkronla();
    } catch (_) {}
    // en az bir süre dönen simge görünsün
    await Future<void>.delayed(const Duration(milliseconds: 500));
    int? n;
    try {
      n = await widget.motor.kayitSayaci?.call();
    } catch (_) {}
    if (!mounted) return;
    _bitisMetni = esitlendiMetni(n);
    setState(
      () => _durum = widget.motor.cevrimdisi
          ? EsitlemeDurumu.cevrimdisi
          : EsitlemeDurumu.tamam,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _durum = EsitlemeDurumu.bos);
    _asiri = 0;
    _tetiklendi = false;
    _kayma.value = 0;
  }

  bool _kaydirma(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (_durum != EsitlemeDurumu.bos)
      return false; // eşitleme/sonuç gösteriliyor: kapanana dek açık kalır
    if (n is OverscrollNotification && n.overscroll < 0) {
      if (_asiri == 0) HapticFeedback.lightImpact(); // çekme başladı
      _asiri -= n.overscroll;
      _kayma.value = cekmeKaymasi(_asiri);
      if (_asiri >= _esik && !_tetiklendi) {
        _tetiklendi = true;
        HapticFeedback.mediumImpact(); // eşik aşıldı: eşitleme başlıyor
        titret();
        _esitle();
      }
    } else if (n is ScrollEndNotification ||
        (n is ScrollUpdateNotification && n.metrics.pixels > 0)) {
      _asiri = 0;
      _tetiklendi = false;
      _kayma.value = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _kaydirma,
        child: ValueListenableBuilder<double>(
          valueListenable: _kayma,
          child: widget.child,
          builder: (c, k, ch) => Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: EsitlemeGostergesi(
                  durum: _durum,
                  kayma: k,
                  bitisMetni: _bitisMetni,
                ),
              ),
              Positioned.fill(
                child: CekmeKaydirici(kayma: k, child: ch!),
              ),
            ],
          ),
        ),
      );
}
