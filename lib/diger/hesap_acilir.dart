import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/oturum.dart';
import '../tema/tema.dart';

/// Alt çubuktaki Profil düğmesinin üstünde, YUKARI doğru açılan kompakt hesap menüsü: tasarım, gündüz/gece, vurgu rengi;
/// altında Profilim, Hakkında ve Sistemden Çıkış. Tema seçimi anında uygulanır ve hesaba kaydedilir (menü açık kalır, değişimi canlı görürsünüz).
/// [kaynak]: menünün hizalanacağı düğmenin ekran dikdörtgeni.
Future<void> hesapAcilirAc(
  BuildContext context, {
  required Oturum oturum,
  required Rect kaynak,
  required VoidCallback profilim,
  required VoidCallback hakkinda,
  required VoidCallback cikis,
  bool asagi = false,
}) {
  final mesaj = ScaffoldMessenger.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withValues(alpha: 0.22),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (c, _, _) {
      final ekran = MediaQuery.sizeOf(c);
      final ust = MediaQuery.paddingOf(c).top;
      return Stack(
        children: [
          Positioned(
            top: asagi ? kaynak.bottom + 8 : null,
            bottom: asagi ? null : ekran.height - kaynak.top + 10,
            right: (ekran.width - kaynak.right).clamp(8.0, ekran.width),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: asagi
                    ? ekran.height - kaynak.bottom - 24
                    : ekran.height - (ekran.height - kaynak.top) - ust - 24,
              ),
              child: _Acilir(
                oturum: oturum,
                mesaj: mesaj,
                profilim: () {
                  Navigator.of(c).pop();
                  profilim();
                },
                hakkinda: () {
                  Navigator.of(c).pop();
                  hakkinda();
                },
                cikis: () {
                  Navigator.of(c).pop();
                  cikis();
                },
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (c, anim, _, child) {
      final e = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: e,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(e),
          alignment: asagi ? Alignment.topRight : Alignment.bottomRight,
          child: child,
        ),
      );
    },
  );
}

class _Acilir extends StatelessWidget {
  const _Acilir({
    required this.oturum,
    required this.mesaj,
    required this.profilim,
    required this.hakkinda,
    required this.cikis,
  });

  final Oturum oturum;
  final ScaffoldMessengerState mesaj;
  final VoidCallback profilim;
  final VoidCallback hakkinda;
  final VoidCallback cikis;

  Future<void> _uygula(TemaTercihi t) async {
    HapticFeedback.selectionClick();
    final kaydedildi = await oturum.temaKaydet(t);
    if (!kaydedildi) {
      mesaj
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
        final cs = tema.colorScheme;
        final koyu = tema.brightness == Brightness.dark;
        final v = cs.primary;
        final y = (oturum.ben?['yonetici'] as Map?) ?? const {};
        final ad = '${y['adi'] ?? ''}'.trim();
        return Container(
          width: 292,
          padding: const EdgeInsets.all(1.2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                v.withValues(alpha: 0.6),
                cs.outlineVariant.withValues(alpha: 0.4),
                v.withValues(alpha: 0.3),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: koyu ? 0.55 : 0.22),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: v.withValues(alpha: 0.18),
                blurRadius: 40,
                spreadRadius: -6,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Material(
                color: cs.surface.withValues(alpha: koyu ? 0.84 : 0.92),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            padding: const EdgeInsets.all(1.6),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Marka.altin, Marka.altinKoyu],
                              ),
                            ),
                            child: ClipOval(
                              child: oturum.profilFoto == null
                                  ? ColoredBox(
                                      color: cs.surface,
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    )
                                  : Image.memory(
                                      oturum.profilFoto!,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      gaplessPlayback: true,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              ad.isEmpty ? 'Hesabım' : ad,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tema.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _Baslik('Tasarım', tema),
                      Row(
                        children: [
                          for (final s in stilAdlari.entries) ...[
                            Expanded(
                              child: _Hap(
                                ad: s.value,
                                secili: t.stil == s.key,
                                tikla: () => _uygula(t.kopya(stil: s.key)),
                              ),
                            ),
                            if (s.key != stilAdlari.keys.last)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                      _Baslik('Gündüz / gece', tema),
                      Row(
                        children: [
                          Expanded(
                            child: _Hap(
                              ad: 'Gündüz',
                              ikon: Icons.light_mode_outlined,
                              secili: t.mod == 'light',
                              tikla: () => _uygula(t.kopya(mod: 'light')),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _Hap(
                              ad: 'Gece',
                              ikon: Icons.dark_mode_outlined,
                              secili: t.mod == 'dark',
                              tikla: () => _uygula(t.kopya(mod: 'dark')),
                            ),
                          ),
                        ],
                      ),
                      _Baslik('Vurgu rengi', tema),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in vurguRenkleri.entries)
                            _Nokta(
                              renk: erisilebilirVurgu(r.key, t.koyu),
                              ad: r.value.ad,
                              secili: t.renk == r.key,
                              tikla: () => _uygula(t.kopya(renk: r.key)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: cs.outlineVariant),
                      _Satir(
                        ikon: Icons.person_outline_rounded,
                        ad: 'Profilim',
                        tikla: profilim,
                      ),
                      _Satir(
                        ikon: Icons.info_outline_rounded,
                        ad: 'Uygulama Hakkında',
                        tikla: hakkinda,
                      ),
                      _Satir(
                        ikon: Icons.logout_rounded,
                        ad: 'Sistemden Çıkış',
                        tikla: cikis,
                        tehlike: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin, this.tema);

  final String metin;
  final ThemeData tema;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 0, 7),
    child: Text(
      metin,
      style: tema.textTheme.labelSmall?.copyWith(
        color: tema.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _Hap extends StatelessWidget {
  const _Hap({
    required this.ad,
    required this.secili,
    required this.tikla,
    this.ikon,
  });

  final String ad;
  final bool secili;
  final VoidCallback tikla;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = cs.primary;
    return GestureDetector(
      onTap: tikla,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: secili
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(v, Colors.white, 0.14)!,
                    Color.lerp(v, Colors.black, 0.24)!,
                  ],
                )
              : null,
          color: secili ? null : cs.onSurface.withValues(alpha: 0.06),
          boxShadow: secili
              ? [
                  BoxShadow(
                    color: v.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (ikon != null) ...[
              Icon(
                ikon,
                size: 15,
                color: secili ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: secili ? FontWeight.w800 : FontWeight.w600,
                  color: secili ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nokta extends StatelessWidget {
  const _Nokta({
    required this.renk,
    required this.ad,
    required this.secili,
    required this.tikla,
  });

  final Color renk;
  final String ad;
  final bool secili;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: ad,
      child: GestureDetector(
        onTap: tikla,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 28,
          height: 28,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: secili ? renk : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: renk,
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: secili
                ? Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: renk.computeLuminance() > 0.55
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.ikon,
    required this.ad,
    required this.tikla,
    this.tehlike = false,
  });

  final IconData ikon;
  final String ad;
  final VoidCallback tikla;
  final bool tehlike;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final renk = tehlike ? cs.error : cs.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: tikla,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(ikon, size: 20, color: renk),
            const SizedBox(width: 12),
            Text(
              ad,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: renk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
