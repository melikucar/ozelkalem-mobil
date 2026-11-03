import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../veri/yazi_formatlari.dart';
import '../../veri/yazisma.dart';
import '../programlar/program_ortak.dart';

/// "30 Eki 2026" biçimi.
String yazismaTarihYaz(DateTime d) =>
    '${d.day} ${trAylarKisa[d.month]} ${d.year}';

/// Kişiye göre sabit vurgu rengi (listede aynı kişiye yazılanlar aynı renkte görünür).
Color yazismaRengi(String kisi, {bool koyu = false}) {
  var h = 0;
  for (final c in kisi.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(
    1,
    (h % 360).toDouble(),
    0.55,
    koyu ? 0.62 : 0.40,
  ).toColor();
}

class YazismaRozet extends StatelessWidget {
  const YazismaRozet({
    super.key,
    required this.metin,
    this.renk,
    this.ikon,
    this.nokta = false,
  });

  final String metin;
  final Color? renk;
  final IconData? ikon;
  final bool nokta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = renk ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nokta)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          if (ikon != null) ...[
            Icon(ikon, size: 12, color: c),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              metin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Liste kartı: muhatap, ünvan, metin özeti, ilgili kişi ve kaydeden; bekleyen / sorunlu işaretleri.
class YazismaKarti extends StatelessWidget {
  const YazismaKarti({
    super.key,
    required this.yazisma,
    required this.kaydeden,
    required this.tikla,
    this.sorunlu = false,
  });

  final Yazisma yazisma;
  final String kaydeden;
  final VoidCallback tikla;
  final bool sorunlu;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final y = yazisma;
    final koyu = tema.brightness == Brightness.dark;
    final renk = yazismaRengi(y.kisi, koyu: koyu);
    final ozet = y.icerikDuz.replaceAll('\n', ' ').trim();
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
                Container(width: 4, color: renk),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              yazismaTarihYaz(y.tarih),
                              style: tema.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 11.5,
                              ),
                            ),
                            const Spacer(),
                            if (sorunlu)
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: Color(0xFFE11D48),
                              )
                            else if (y.bekleyen)
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          y.kisi.isEmpty ? '(MUHATAP YOK)' : y.kisiBuyuk,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        if (y.unvan.isNotEmpty)
                          Text(
                            y.unvan,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        if (ozet.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            ozet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                        if (y.ilgili.isNotEmpty || kaydeden.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (y.ilgili.isNotEmpty)
                                YazismaRozet(
                                  metin: trBuyuk(y.ilgili),
                                  renk: renk,
                                  ikon: y.talepBagli
                                      ? Icons.assignment_ind_outlined
                                      : Icons.person_outline_rounded,
                                ),
                              if (kaydeden.isNotEmpty)
                                YazismaRozet(
                                  metin: kaydeden,
                                  ikon: Icons.edit_outlined,
                                ),
                            ],
                          ),
                        ],
                      ],
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

/// A4 kağıt biçiminde yazı önizlemesi (web yazı ayrıntısıyla aynı düzen: logo ve makam başlığı, "Sayın …", metin, imza, alt bilgi).
/// Kağıt 595 birim genişliğinde çizilir ve ekrana sığacak şekilde küçültülür.
class YazismaKagidi extends StatelessWidget {
  const YazismaKagidi({
    super.key,
    required this.kisi,
    required this.unvan,
    required this.metin,
    required this.logo,
    required this.imza,
    required this.imzaUnvan,
    required this.imzaUnvan2,
    required this.altYazi,
    this.makamLogo,
    this.makamImza,
    this.makam,
  });

  final String kisi;
  final String unvan;
  final String metin;
  final bool logo;
  final bool imza;
  final bool imzaUnvan;
  final bool imzaUnvan2;
  final bool altYazi;
  final Uint8List? makamLogo;
  final Uint8List? makamImza;
  final Map<String, dynamic>? makam;

  static const _genislik = 595.0;

  String _m(String k) => (makam?[k] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final adi = trBuyuk(_m('adi'));
    final unvani = _m('unvan');
    final unvani2 = _m('unvan_2');
    final logoTercihi = _m('logo_tercihi');
    const yazi = TextStyle(
      fontFamily: 'serif',
      color: Colors.black,
      fontSize: 15,
      height: 1.45,
    );
    final kagit = Container(
      width: _genislik,
      constraints: const BoxConstraints(minHeight: _genislik * 1.414),
      padding: const EdgeInsets.fromLTRB(56, 44, 56, 40),
      color: Colors.white,
      child: DefaultTextStyle(
        style: yazi,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Visibility(
              visible: logo,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Center(
                child: Column(
                  children: [
                    if (logoTercihi == 'kurum' && makamLogo != null)
                      Image.memory(makamLogo!, width: 80, height: 80)
                    else
                      Image.asset(
                        'assets/marka/logo_tbmm.png',
                        width: 80,
                        height: 80,
                      ),
                    const SizedBox(height: 10),
                    if (adi.isNotEmpty)
                      Text(
                        adi,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    if (unvani.isNotEmpty)
                      Text(
                        unvani,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                    if (unvani2.isNotEmpty)
                      Text(
                        unvani2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 44),
            Text(
              'Sayın ${kisi.trim().isEmpty ? '………………………' : kisi.trim()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (unvan.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  unvan.trim(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 22),
            Text(
              metin.trim().isEmpty ? 'Yazı metni burada görünecek…' : metin,
              textAlign: TextAlign.justify,
              style: metin.trim().isEmpty
                  ? yazi.copyWith(color: Colors.black38)
                  : null,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Spacer(flex: 6),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      if (imza && makamImza != null)
                        Image.memory(
                          makamImza!,
                          height: 70,
                          fit: BoxFit.contain,
                        )
                      else
                        const SizedBox(height: 70),
                      Visibility(
                        visible: imzaUnvan,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Column(
                          children: [
                            Text(
                              adi,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              unvani,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Visibility(
                        visible: imzaUnvan2,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Text(
                          unvani2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 60),
            Visibility(
              visible: altYazi,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tel.: ${_m('telefon')}'),
                  Text('Faks: ${_m('fax')}'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text('e-posta: ${_m('mail')}')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          trBuyuk(_m('adres')),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: kagit,
        ),
      ),
    );
  }
}
