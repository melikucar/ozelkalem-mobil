import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../api/api_istemci.dart';
import '../../veri/tbmm.dart';
import '../programlar/program_ortak.dart';
import '../raporlar/rapor_ortak.dart' show raporRenkleri;

/// Önerge türüne göre ikon (web ile aynı eşleşme).
IconData tbmmIkonu(int tablo) => switch (tablo) {
  1 => Icons.description_outlined,
  2 => Icons.help_outline_rounded,
  3 => Icons.record_voice_over_outlined,
  4 => Icons.travel_explore_rounded,
  _ => Icons.account_balance_outlined,
};

Color tbmmRengi(int tablo) =>
    raporRenkleri[(tablo - 1).abs() % raporRenkleri.length];

/// "30 Eki 2026"
String tbmmTarihKisa(DateTime d) =>
    '${d.day} ${trAylarKisa[d.month]} ${d.year}';

/// Sunucuda üretilen PDF'i indirip cihazdaki uygulamayla açar. Hata olursa mesaj döner (null: sorun yok).
Future<String?> tbmmPdfAc(ApiIstemci api, String yol, String ad) async {
  try {
    final r = await api.dosyaIndir(yol);
    final dizin = Directory(
      p.join((await getTemporaryDirectory()).path, 'tbmm'),
    );
    if (!dizin.existsSync()) dizin.createSync(recursive: true);
    final dosya = p.join(dizin.path, ad);
    await File(dosya).writeAsBytes(r.bayt, flush: true);
    final s = await OpenFilex.open(dosya, type: 'application/pdf');
    if (s.type == ResultType.noAppToOpen) {
      return 'PDF dosyasını açabilecek uygulama yok.';
    }
    return s.type == ResultType.done ? null : 'Dosya açılamadı.';
  } on ApiHata catch (e) {
    return e.agHatasi ? 'PDF için internet bağlantısı gerekir.' : e.mesaj;
  }
}

class TbmmRozet extends StatelessWidget {
  const TbmmRozet({super.key, required this.metin, this.renk, this.ikon});

  final String metin;
  final Color? renk;
  final IconData? ikon;

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

/// Liste kartı: tür renginde şerit, ad, tarih, içerik özeti; tür, ek dosya sayısı ve kaydeden rozetleri.
class TbmmKarti extends StatelessWidget {
  const TbmmKarti({
    super.key,
    required this.kayit,
    required this.turAdi,
    required this.kaydeden,
    required this.tikla,
    this.sorunlu = false,
  });

  final Tbmm kayit;
  final String turAdi;
  final String kaydeden;
  final VoidCallback tikla;
  final bool sorunlu;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final t = kayit;
    final renk = tbmmRengi(t.tablo);
    final ozet = t.icerikDuz.replaceAll('\n', ' ').trim();
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
                              tbmmTarihKisa(t.tarih),
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
                            else if (t.bekleyen)
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          t.adi.trim().isEmpty ? '(ADSIZ)' : t.adBuyuk,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.2,
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
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (turAdi.isNotEmpty)
                              TbmmRozet(
                                metin: turAdi,
                                renk: renk,
                                ikon: tbmmIkonu(t.tablo),
                              ),
                            if (t.ek > 0)
                              TbmmRozet(
                                metin: '${t.ek} ek',
                                ikon: Icons.attach_file_rounded,
                              ),
                            if (kaydeden.isNotEmpty)
                              TbmmRozet(
                                metin: kaydeden,
                                ikon: Icons.edit_outlined,
                              ),
                          ],
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
