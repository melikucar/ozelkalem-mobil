import 'package:flutter/material.dart';

import '../api/oturum.dart';
import '../tema/tema.dart';

/// "Görünüm" sayfası: web panelindeki tema menüsünün karşılığı (stil × mod × vurgu rengi). Seçim anında uygulanır ve hesaba kaydedilir.
Future<void> temaSeciciAc(BuildContext context, Oturum oturum) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _TemaSecici(oturum: oturum),
  );
}

class _TemaSecici extends StatelessWidget {
  const _TemaSecici({required this.oturum});

  final Oturum oturum;

  Future<void> _uygula(BuildContext context, TemaTercihi t) async {
    final kaydedildi = await oturum.temaKaydet(t);
    if (!kaydedildi && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Tema bu cihazda uygulandı; hesabınıza kaydedilemedi (bağlantı yok).',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: oturum,
      builder: (context, _) {
        final t = oturum.tema;
        final tema = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Görünüm',
                  style: tema.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Web panelindeki tercihinizle aynıdır; birinde değiştirince diğerinde de değişir.',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text('Tasarım', style: tema.textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final s in stilAdlari.entries) ...[
                      Expanded(
                        child: _StilKarti(
                          stil: s.key,
                          ad: s.value,
                          secili: t.stil == s.key,
                          tercih: t,
                          tikla: () => _uygula(context, t.kopya(stil: s.key)),
                        ),
                      ),
                      if (s.key != stilAdlari.keys.last)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                Text('Gündüz / gece', style: tema.textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: 'light',
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Gündüz'),
                      ),
                      ButtonSegment(
                        value: 'dark',
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Gece'),
                      ),
                    ],
                    selected: {t.mod},
                    onSelectionChanged: (s) =>
                        _uygula(context, t.kopya(mod: s.first)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Vurgu rengi', style: tema.textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final r in vurguRenkleri.entries)
                      _Damla(
                        anahtar: r.key,
                        ad: r.value.ad,
                        secili: t.renk == r.key,
                        koyu: t.koyu,
                        tikla: () => _uygula(context, t.kopya(renk: r.key)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Stilin küçük önizlemesi (web'deki tema kartlarının karşılığı).
class _StilKarti extends StatelessWidget {
  const _StilKarti({
    required this.stil,
    required this.ad,
    required this.secili,
    required this.tercih,
    required this.tikla,
  });

  final String stil, ad;
  final bool secili;
  final TemaTercihi tercih;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vurgu = erisilebilirVurgu(tercih.renk, tercih.koyu);
    final koyu = tercih.koyu;
    final sayfa = koyu ? const Color(0xFF2A3037) : const Color(0xFFDFE3E8);
    final icerik = koyu ? const Color(0x24FFFFFF) : const Color(0x1F000000);
    final ayrac = koyu ? const Color(0xFF1D2227) : Colors.white;

    Widget onizleme;
    switch (stil) {
      case 'kurumsal':
        onizleme = Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 16,
              child: Container(color: ayrac),
            ),
            Positioned(
              left: 16,
              right: 0,
              top: 0,
              height: 9,
              child: Container(
                decoration: BoxDecoration(
                  color: ayrac,
                  border: Border(bottom: BorderSide(color: vurgu, width: 2)),
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 5,
              top: 17,
              bottom: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: icerik,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        );
      case 'cam':
        onizleme = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                karistir(const Color(0xFF101626), vurgu, 0.55),
                const Color(0xFF0A0F1D),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 4,
                top: 5,
                bottom: 5,
                width: 14,
                child: _camParca(),
              ),
              Positioned(
                left: 22,
                right: 5,
                top: 5,
                height: 9,
                child: _camParca(),
              ),
              Positioned(
                left: 22,
                right: 5,
                top: 18,
                bottom: 5,
                child: _camParca(),
              ),
            ],
          ),
        );
      default:
        onizleme = Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 16,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF212529),
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(6),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 21,
              right: 5,
              top: 4,
              height: 9,
              child: Container(
                decoration: BoxDecoration(
                  color: vurgu,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            Positioned(
              left: 21,
              right: 5,
              top: 17,
              bottom: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: icerik,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        );
    }

    return Semantics(
      button: true,
      selected: secili,
      label: '$ad tasarımı',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: tikla,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: secili
                  ? tema.colorScheme.primary
                  : tema.colorScheme.outlineVariant,
              width: secili ? 2.5 : 1.5,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  height: 54,
                  color: stil == 'cam' ? null : sayfa,
                  child: onizleme,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                ad,
                style: tema.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _camParca() => Container(
    decoration: BoxDecoration(
      color: const Color(0x47FFFFFF),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0x66FFFFFF)),
    ),
  );
}

class _Damla extends StatelessWidget {
  const _Damla({
    required this.anahtar,
    required this.ad,
    required this.secili,
    required this.koyu,
    required this.tikla,
  });

  final String anahtar, ad;
  final bool secili, koyu;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final renk = vurguRenkleri[anahtar]!.renk;
    final tema = Theme.of(context);
    final onRenk = renk.computeLuminance() > 0.5
        ? const Color(0xFF212529)
        : Colors.white;
    return Semantics(
      button: true,
      selected: secili,
      label: ad,
      child: Tooltip(
        message: ad,
        child: InkResponse(
          onTap: tikla,
          radius: 28,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: renk,
              shape: BoxShape.circle,
              border: Border.all(
                color: secili
                    ? tema.colorScheme.onSurface
                    : tema.colorScheme.outlineVariant,
                width: secili ? 3 : 1.5,
              ),
            ),
            child: secili ? Icon(Icons.check, color: onRenk, size: 22) : null,
          ),
        ),
      ),
    );
  }
}
