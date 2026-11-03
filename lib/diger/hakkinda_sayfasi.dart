import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diger/modul_hero.dart';
import '../tema/tema.dart';

/// Uygulama Hakkında: marka, sürüm, ürün özeti, geliştirici/iletişim bilgileri ve yasal not.
class HakkindaSayfasi extends StatelessWidget {
  const HakkindaSayfasi({super.key, required this.surum});

  final String surum;

  static const _site = 'https://www.ozelkalemotomasyonu.com';
  static const _telefon = '+905336685245';
  static const _eposta = 'melikucar@gmail.com';

  static const _ozellikler = <(IconData, String)>[
    (Icons.assignment_outlined, 'Talep, faaliyet, program ve randevu takibi'),
    (Icons.contacts_outlined, 'Telefon rehberi ve görüşme kayıtları'),
    (Icons.mail_outline_rounded, 'Yazışma hazırlama; PDF ve Word çıktısı'),
    (Icons.insights_outlined, 'Raporlar, grafikler ve harita görünümü'),
    (Icons.cloud_sync_outlined, 'Çevrimdışı çalışma ve otomatik eşitleme'),
  ];

  Future<void> _ac(BuildContext context, String adres) async {
    final tamam = await launchUrl(
      Uri.parse(adres),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!tamam && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final yil = DateTime.now().year;

    BoxDecoration kart() => BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: (acik ? Marka.lacivert : Colors.black).withValues(
            alpha: acik ? 0.08 : 0.35,
          ),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );

    Widget baslik(String metin) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Text(
        metin,
        style: tema.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );

    Widget satir(
      IconData ikon,
      String etiket,
      String deger, {
      VoidCallback? tikla,
      bool son = false,
    }) => Column(
      children: [
        InkWell(
          onTap: tikla,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(ikon, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        etiket,
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        deger,
                        style: tema.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tikla != null ? cs.primary : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tikla != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        if (!son) Divider(height: 1, indent: 58, color: cs.outlineVariant),
      ],
    );

    return Scaffold(
      body: Column(
        children: [
          const ModulHero(
            geri: true,
            ikon: Icons.info_outline_rounded,
            baslik: 'Uygulama Hakkında',
            altBaslik: 'Sürüm, iletişim ve yasal bilgiler',
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.3, 1],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: cs.surface,
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.primary.withValues(alpha: 0.22),
                                      blurRadius: 28,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/marka/isaret.png',
                                  width: 68,
                                  height: 68,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Özel Kalem Otomasyonu',
                                textAlign: TextAlign.center,
                                style: tema.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Kurumsal Akış ve Yönetim Platformu',
                                textAlign: TextAlign.center,
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  'Sürüm $surum',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          baslik('Neler sunar'),
                          Container(
                            decoration: kart(),
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              children: [
                                for (final o in _ozellikler)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(o.$1, size: 20, color: cs.primary),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            o.$2,
                                            style: tema.textTheme.bodyMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          baslik('Geliştirici ve iletişim'),
                          Container(
                            decoration: kart(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Column(
                              children: [
                                satir(
                                  Icons.badge_outlined,
                                  'Geliştirici',
                                  'Melik UÇAR',
                                ),
                                satir(
                                  Icons.call_outlined,
                                  'İletişim telefonu',
                                  '+90 (533) 668 52 45',
                                  tikla: () => _ac(context, 'tel:$_telefon'),
                                ),
                                satir(
                                  Icons.alternate_email_rounded,
                                  'E-posta',
                                  _eposta,
                                  tikla: () => _ac(context, 'mailto:$_eposta'),
                                ),
                                satir(
                                  Icons.language_rounded,
                                  'Web sitesi',
                                  'www.ozelkalemotomasyonu.com',
                                  tikla: () => _ac(context, _site),
                                  son: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            '© $yil Özel Kalem Otomasyonu. Tüm hakları saklıdır.',
                            textAlign: TextAlign.center,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Bu uygulamadaki veriler kurumunuza aittir ve yetkisiz paylaşılamaz.',
                            textAlign: TextAlign.center,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                              fontSize: 11,
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
        ],
      ),
    );
  }
}
