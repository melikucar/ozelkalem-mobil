import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../veri/yazi_formatlari.dart';
import '../../veri/rehber.dart';
import '../../veri/tarih_yardimci.dart' show telefonRakamlari;
import '../programlar/program_ortak.dart';

/// Sunucudan gelen rehber referansı: kişi kategorileri, görüşme durumları, kaydedenler.
class RehberReferans {
  RehberReferans(this.v);

  final Map<String, dynamic> v;

  bool get bos => v.isEmpty;

  List<Map<String, dynamic>> _liste(String k) => [
    for (final x in (v[k] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  List<Map<String, dynamic>> get kategoriler => _liste('kategoriler');
  List<Map<String, dynamic>> get durumlar => _liste('durumlar');
  List<Map<String, dynamic>> get kaydedenler => _liste('kaydedenler');

  String _ad(List<Map<String, dynamic>> l, int no) {
    for (final k in l) {
      if (k['no'] == no) return '${k['adi']}';
    }
    return '';
  }

  String kategoriAdi(int no) => _ad(kategoriler, no);
  String durumAdi(int no) => _ad(durumlar, no);
  String kaydedenAdi(int no) => _ad(kaydedenler, no);
}

/// Görüşme durumunun rengi (1 Biz aradık/görüşüldü, 2 görüşülemedi, 3 Onlar aradı/görüşüldü, 4 görüşülemedi).
Color gorusmeDurumRengi(int d) => switch (d) {
  1 => const Color(0xFF16A34A),
  2 => const Color(0xFFD97706),
  3 => const Color(0xFF2563EB),
  4 => const Color(0xFFE11D48),
  _ => const Color(0xFF64748B),
};

IconData gorusmeDurumIkonu(int d) => switch (d) {
  1 => Icons.call_made_rounded,
  2 => Icons.phone_missed_rounded,
  3 => Icons.call_received_rounded,
  4 => Icons.phone_missed_rounded,
  _ => Icons.call_rounded,
};

/// Kategori başına sabit vurgu rengi.
Color rehberKategoriRengi(int katno, {bool koyu = false}) => HSLColor.fromAHSL(
  1,
  ((katno * 61) % 360).toDouble(),
  0.55,
  koyu ? 0.62 : 0.42,
).toColor();

Future<void> telefonAra(String tel) async {
  final r = telefonRakamlari(tel);
  if (r.isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: '+$r'));
}

Future<void> whatsappAc(String tel) async {
  final r = telefonRakamlari(tel);
  if (r.isEmpty) return;
  await launchUrl(
    Uri.parse('https://wa.me/$r'),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> smsAc(String tel) async {
  final r = telefonRakamlari(tel);
  if (r.isEmpty) return;
  await launchUrl(Uri(scheme: 'sms', path: '+$r'));
}

Future<void> epostaAc(String adres) async {
  if (adres.trim().isEmpty) return;
  await launchUrl(Uri(scheme: 'mailto', path: adres.trim()));
}

Future<bool> haritadaAc(String adres) async {
  final q = Uri.encodeComponent(adres.trim());
  if (q.isEmpty) return false;
  var tamam = await launchUrl(
    Uri.parse('geo:0,0?q=$q'),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!tamam) {
    tamam = await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
  }
  return tamam;
}

/// "0532 111 22 33" gibi kayıtlı biçimi olduğu gibi gösterir; dahili varsa ekler.
String telefonYazisi(String tel, [String dahili = '']) {
  final t = tel.trim();
  if (t.isEmpty) return '';
  return dahili.trim().isEmpty ? t : '$t · dahili ${dahili.trim()}';
}

/// Tek dokunuşla aranabilen telefon satırı: etiket, numara, ara / WhatsApp / SMS düğmeleri.
class TelefonSatiri extends StatelessWidget {
  const TelefonSatiri({
    super.key,
    required this.etiket,
    required this.numara,
    this.dahili = '',
    this.ikon = Icons.phone_outlined,
    this.mesajlasma = false,
  });

  final String etiket;
  final String numara;
  final String dahili;
  final IconData ikon;

  /// true: WhatsApp ve SMS düğmeleri de gösterilir (cep telefonları).
  final bool mesajlasma;

  @override
  Widget build(BuildContext context) {
    if (numara.trim().isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(ikon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => telefonAra(numara),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiket,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    telefonYazisi(numara, dahili),
                    style: tema.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Mini(
            ikon: Icons.call_rounded,
            renk: const Color(0xFF16A34A),
            tikla: () => telefonAra(numara),
          ),
          if (mesajlasma) ...[
            const SizedBox(width: 6),
            _Mini(
              ikon: Icons.chat_rounded,
              renk: const Color(0xFF0E9F6E),
              tikla: () => whatsappAc(numara),
            ),
            const SizedBox(width: 6),
            _Mini(
              ikon: Icons.sms_outlined,
              renk: cs.primary,
              tikla: () => smsAc(numara),
            ),
          ],
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.ikon, required this.renk, required this.tikla});

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
        width: 36,
        height: 36,
        child: Icon(ikon, size: 18, color: renk),
      ),
    ),
  );
}

/// Kişi satırının sabit yüksekliği (harf çubuğuyla anında konumlanabilmek için liste sabit ölçülüdür).
const double kisiSatirBoyu = 76;

/// Rehber listesindeki kişi satırı: ad, ünvan, ilk telefon, kategori noktası, kara liste uyarısı; sağda tek dokunuşla arama.
class KisiSatiri extends StatelessWidget {
  const KisiSatiri({
    super.key,
    required this.kisi,
    required this.kategoriAdi,
    required this.tikla,
    this.sorunlu = false,
    this.ayrac = true,
  });

  final Kisi kisi;
  final String kategoriAdi;
  final VoidCallback tikla;
  final bool sorunlu;
  final bool ayrac;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final koyu = tema.brightness == Brightness.dark;
    final k = kisi;
    final renk = rehberKategoriRengi(k.katno, koyu: koyu);
    final tel = k.anaTelefon;
    return InkWell(
      onTap: tikla,
      child: Container(
        height: kisiSatirBoyu,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        decoration: BoxDecoration(
          border: ayrac
              ? Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: k.kara ? const Color(0xFFE11D48) : renk,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trBuyuk(k.adi),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (k.kara) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.block_rounded,
                          size: 15,
                          color: Color(0xFFE11D48),
                        ),
                      ],
                      if (sorunlu) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: Color(0xFFE11D48),
                        ),
                      ] else if (k.bekleyen) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.cloud_upload_outlined,
                          size: 15,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  if (k.unvan.trim().isNotEmpty)
                    Text(
                      k.unvan.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  Row(
                    children: [
                      if (tel.isNotEmpty)
                        Text(
                          tel,
                          style: tema.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      if (tel.isNotEmpty && kategoriAdi.isNotEmpty)
                        Text(
                          '  ·  ',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      if (kategoriAdi.isNotEmpty)
                        Flexible(
                          child: Text(
                            kategoriAdi,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (tel.isNotEmpty)
              IconButton(
                tooltip: 'Ara',
                onPressed: () => telefonAra(tel),
                icon: const Icon(
                  Icons.call_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Görüşme kartı: durum simgesi, kişi, konu, tarih; ulaşılamayanlar için "tekrar ara".
class GorusmeKarti extends StatelessWidget {
  const GorusmeKarti({
    super.key,
    required this.gorusme,
    required this.ref,
    required this.tikla,
    this.sorunlu = false,
  });

  final Gorusme gorusme;
  final RehberReferans ref;
  final VoidCallback tikla;
  final bool sorunlu;

  static String zamanYaz(DateTime t) =>
      '${t.day} ${trAylarKisa[t.month]} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final g = gorusme;
    final renk = gorusmeDurumRengi(g.d1);
    final yazi = Color.lerp(
      renk,
      tema.brightness == Brightness.light ? Colors.black : Colors.white,
      0.35,
    )!;
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: renk.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: renk.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(
                            gorusmeDurumIkonu(g.d1),
                            color: yazi,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      zamanYaz(g.t1),
                                      style: tema.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  if (sorunlu)
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFE11D48),
                                    )
                                  else if (g.bekleyen)
                                    Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                ],
                              ),
                              Text(
                                trBuyuk(g.adi),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              if (g.konu.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    g.konu.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _Rozet(
                                    metin: ref.durumAdi(g.d1),
                                    renk: renk,
                                    yazi: yazi,
                                  ),
                                  if (g.d2 > 0)
                                    _Rozet(
                                      metin: 'Takip: ${ref.durumAdi(g.d2)}',
                                      renk: gorusmeDurumRengi(g.d2),
                                      yazi: Color.lerp(
                                        gorusmeDurumRengi(g.d2),
                                        tema.brightness == Brightness.light
                                            ? Colors.black
                                            : Colors.white,
                                        0.35,
                                      )!,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (g.tel1.trim().isNotEmpty)
                          IconButton(
                            tooltip: g.ulasilamadi ? 'Tekrar ara' : 'Ara',
                            onPressed: () => telefonAra(g.tel1),
                            icon: Icon(
                              Icons.call_rounded,
                              color: g.ulasilamadi
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF16A34A),
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
    );
  }
}

class _Rozet extends StatelessWidget {
  const _Rozet({required this.metin, required this.renk, required this.yazi});

  final String metin;
  final Color renk;
  final Color yazi;

  @override
  Widget build(BuildContext context) {
    if (metin.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: renk.withValues(alpha: 0.4)),
      ),
      child: Text(
        metin,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: yazi,
        ),
      ),
    );
  }
}
