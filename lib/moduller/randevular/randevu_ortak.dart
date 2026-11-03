import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tema/tema.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/program.dart' show programRengi;
import '../../veri/randevu.dart';
import '../../veri/tarih_yardimci.dart' show telefonRakamlari;
import '../programlar/program_ortak.dart';

/// Sunucudan gelen randevu referansı (kategori, durum, süre, rehber kategorileri, kaydedenler …).
class RandevuReferans {
  RandevuReferans(this.v);

  final Map<String, dynamic> v;

  bool get bos => v.isEmpty;

  List<Map<String, dynamic>> _liste(String k) => [
    for (final x in (v[k] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  List<Map<String, dynamic>> get kategoriler => _liste('kategoriler');
  List<Map<String, dynamic>> get durumlar => _liste('durumlar');
  List<Map<String, dynamic>> get sureler => _liste('sureler');
  List<Map<String, dynamic>> get hatirlaticilar => _liste('hatirlaticilar');
  List<Map<String, dynamic>> get rehberKategorileri =>
      _liste('rehber_kategorileri');
  List<Map<String, dynamic>> get kaydedenler => _liste('kaydedenler');
  bool get smsHazir => v['sms_hazir'] == true;

  String kategoriAdi(int no) {
    for (final k in kategoriler) {
      if (k['no'] == no) return '${k['adi']}';
    }
    return '';
  }

  String durumAdi(int no) {
    for (final d in durumlar) {
      if (d['no'] == no) return '${d['adi']}';
    }
    return '';
  }

  Color durumRengi(int no) {
    for (final d in durumlar) {
      if (d['no'] == no) return programRengi('${d['renk']}');
    }
    return const Color(0xFF64748B);
  }

  /// "Randevu Verildi…" durumları takvime işlenir.
  bool takvimeAlinir(int durum) {
    for (final d in durumlar) {
      if (d['no'] == durum) return d['takvim'] == true;
    }
    return false;
  }

  String kaydedenAdi(int no) {
    for (final k in kaydedenler) {
      if (k['no'] == no) return '${k['adi']}';
    }
    return '';
  }

  String sureEtiketi(int dk) {
    for (final s in sureler) {
      if (s['dakika'] == dk) return '${s['etiket']}';
    }
    return sureYaz(Duration(minutes: dk));
  }
}

Future<void> randevuAra(String telefon) async {
  final r = telefonRakamlari(telefon);
  if (r.isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: '+$r'));
}

Future<void> randevuWhatsapp(String telefon) async {
  final r = telefonRakamlari(telefon);
  if (r.isEmpty) return;
  await launchUrl(
    Uri.parse('https://wa.me/$r'),
    mode: LaunchMode.externalApplication,
  );
}

/// Göreli etiketin rengi: bugün vurgulu, yarın sıcak, geçti soluk.
Color goreliRenk(BuildContext context, int ton) {
  final cs = Theme.of(context).colorScheme;
  return switch (ton) {
    1 => okunurRenk(context, const Color(0xFF16A34A)),
    2 => okunurRenk(context, const Color(0xFFD97706)),
    3 => cs.onSurfaceVariant,
    _ => cs.primary,
  };
}

/// Açık temada pastel renkleri okunur koyulukta, koyu temada açık tutar (zeminde silik kalmasın).
Color okunurRenk(BuildContext context, Color c) {
  final acik = Theme.of(context).brightness == Brightness.light;
  return acik
      ? Color.lerp(c, Colors.black, 0.42)!
      : Color.lerp(c, Colors.white, 0.35)!;
}

/// Durum rozeti: renkli nokta + ad, yarı saydam zemin.
class DurumRozeti extends StatelessWidget {
  const DurumRozeti({super.key, required this.ad, required this.renk});

  final String ad;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    if (ad.isEmpty) return const SizedBox.shrink();
    final yazi = okunurRenk(context, renk);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.2),
        border: Border.all(color: renk.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              ad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: yazi,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarih "yaprağı": gün numarası + ay kısaltması.
class TarihYapragi extends StatelessWidget {
  const TarihYapragi({super.key, required this.tarih, required this.renk});

  final DateTime tarih;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final yazi = okunurRenk(context, renk);
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [renk.withValues(alpha: 0.28), renk.withValues(alpha: 0.14)],
        ),
        border: Border.all(color: renk.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trAylarKisa[tarih.month].toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: yazi,
            ),
          ),
          Text(
            '${tarih.day}',
            style: TextStyle(
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: yazi,
            ),
          ),
        ],
      ),
    );
  }
}

/// Liste kartı: tarih yaprağı, saat aralığı + göreli etiket, kişi / kurum, ünvan, kategori ve yer, durum rozeti, hızlı arama.
class RandevuKarti extends StatelessWidget {
  const RandevuKarti({
    super.key,
    required this.randevu,
    required this.ref,
    required this.tikla,
    this.sorunlu = false,
    this.tarihGoster = true,
  });

  final Randevu randevu;
  final RandevuReferans ref;
  final VoidCallback tikla;
  final bool sorunlu;
  final bool tarihGoster;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final r = randevu;
    final renk = ref.durumRengi(r.durum);
    final goreli = randevuGoreli(r.bas);
    final gecti = goreli.ton == 3;
    final kat = ref.kategoriAdi(r.katno);
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
          child: Opacity(
            opacity: gecti ? 0.82 : 1,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: renk),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TarihYapragi(tarih: r.bas, renk: renk),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${saatYaz(r.bas)}–${saatYaz(r.bit)}',
                                      style: tema.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (goreli.etiket.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        goreli.etiket,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: goreliRenk(
                                            context,
                                            goreli.ton,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    if (sorunlu)
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 17,
                                        color: Color(0xFFE11D48),
                                      )
                                    else if (r.bekleyen)
                                      Icon(
                                        Icons.cloud_upload_outlined,
                                        size: 17,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    if (r.programNo > 0) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.event_available_rounded,
                                        size: 17,
                                        color: cs.primary,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  trBuyuk(r.adi),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (r.unvan.trim().isNotEmpty)
                                  Text(
                                    trBuyuk(r.unvan),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    DurumRozeti(
                                      ad: ref.durumAdi(r.durum),
                                      renk: renk,
                                    ),
                                    if (kat.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          kat,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tema.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                fontSize: 11.5,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (r.yer.isNotEmpty) ...[
                                  const SizedBox(height: 5),
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
                                          r.yer,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tema.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                fontSize: 11.5,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (telefonRakamlari(r.telefon).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Column(
                                children: [
                                  _MiniDugme(
                                    ikon: Icons.call_rounded,
                                    renk: const Color(0xFF16A34A),
                                    tikla: () => randevuAra(r.telefon),
                                  ),
                                  const SizedBox(height: 6),
                                  _MiniDugme(
                                    ikon: Icons.chat_rounded,
                                    renk: const Color(0xFF0E9F6E),
                                    tikla: () => randevuWhatsapp(r.telefon),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
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

class _MiniDugme extends StatelessWidget {
  const _MiniDugme({
    required this.ikon,
    required this.renk,
    required this.tikla,
  });

  final IconData ikon;
  final Color renk;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) => Material(
    color: renk.withValues(alpha: 0.12),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: tikla,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(ikon, size: 17, color: renk),
      ),
    ),
  );
}

/// Hero içinde zaman sekmeleri (Yaklaşan / Bugün / Geçmiş / Tümü) ve sayaçları.
class ZamanSecici extends StatelessWidget {
  const ZamanSecici({
    super.key,
    required this.secili,
    required this.sayilar,
    required this.sec,
  });

  final RandevuZaman secili;
  final Map<RandevuZaman, int> sayilar;
  final ValueChanged<RandevuZaman> sec;

  static String _ad(RandevuZaman z) => switch (z) {
    RandevuZaman.yaklasan => 'Yaklaşan',
    RandevuZaman.bugun => 'Bugün',
    RandevuZaman.gecmis => 'Geçmiş',
    RandevuZaman.tumu => 'Tümü',
  };

  @override
  Widget build(BuildContext context) {
    const liste = RandevuZaman.values;
    return Container(
      height: 42,
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
                  for (final z in liste)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => sec(z),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _ad(z),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: z == secili
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: z == secili
                                      ? Marka.lacivert
                                      : Colors.white,
                                ),
                              ),
                              if ((sayilar[z] ?? 0) > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${sayilar[z]}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: z == secili
                                        ? Marka.lacivert.withValues(alpha: 0.6)
                                        : Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ],
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
