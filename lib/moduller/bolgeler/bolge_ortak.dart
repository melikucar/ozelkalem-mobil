import 'package:flutter/material.dart';

import '../../veri/bolge.dart';
import '../programlar/program_ortak.dart';

/// Doluluk yüzdesine göre renk (web ile aynı eşikler: ≥70 yüksek, ≥35 orta).
Color bolgeDolulukRengi(double d) => d >= 70
    ? const Color(0xFF1F8A5B)
    : d >= 35
    ? const Color(0xFFD97706)
    : const Color(0xFFE11D48);

String bolgeYuzde(double d) =>
    d == d.roundToDouble() ? '%${d.toInt()}' : '%${d.toStringAsFixed(1)}';

class BolgeRozet extends StatelessWidget {
  const BolgeRozet({super.key, required this.metin, this.renk, this.ikon});

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

/// Doluluk çubuğu: bilgi alanlarının ne kadarının doldurulduğunu gösterir.
class DolulukCubugu extends StatelessWidget {
  const DolulukCubugu({super.key, required this.deger});

  final double deger;

  @override
  Widget build(BuildContext context) {
    final r = bolgeDolulukRengi(deger);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (deger / 100).clamp(0.03, 1.0),
              minHeight: 6,
              color: r,
              backgroundColor: r.withValues(alpha: 0.15),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          bolgeYuzde(deger),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: r,
          ),
        ),
      ],
    );
  }
}

/// Liste kartı: köy/mahalle adı, ilçe · semt, muhtar ve telefonu, doluluk çubuğu.
class BolgeKarti extends StatelessWidget {
  const BolgeKarti({
    super.key,
    required this.kayit,
    required this.tikla,
    this.sorunlu = false,
  });

  final Bolge kayit;
  final VoidCallback tikla;
  final bool sorunlu;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final b = kayit;
    final renk = bolgeDolulukRengi(b.doluluk);
    final nufus = b.alan('toplam_nufus');
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
                            Expanded(
                              child: Text(
                                b.baslik,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (sorunlu)
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: Color(0xFFE11D48),
                              )
                            else if (b.bekleyen)
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                          ],
                        ),
                        if (b.konum.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            b.konum,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (b.muhtar.isNotEmpty)
                              BolgeRozet(
                                metin: b.muhtar,
                                ikon: Icons.badge_outlined,
                              ),
                            if (b.muhtarTelefon.isNotEmpty)
                              BolgeRozet(
                                metin: b.muhtarTelefon,
                                ikon: Icons.phone_outlined,
                              ),
                            if (nufus.isNotEmpty)
                              BolgeRozet(
                                metin: '$nufus nüfus',
                                ikon: Icons.groups_2_outlined,
                                renk: const Color(0xFF1F8A5B),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DolulukCubugu(deger: b.doluluk),
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
