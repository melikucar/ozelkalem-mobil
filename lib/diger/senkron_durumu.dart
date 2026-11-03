import 'package:flutter/material.dart';

import '../senkron/senkron_motoru.dart';

/// Başlıkta senkron durumu: dönen simge / bekleyen değişiklik sayısı / çevrimdışı.
class SenkronDugmesi extends StatelessWidget {
  const SenkronDugmesi({super.key, required this.motor});

  final SenkronMotoru motor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: motor,
      builder: (context, _) {
        if (motor.gosterge) {
          return const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        return IconButton(
          tooltip: 'Şimdi senkronla',
          onPressed: motor.elleSenkronla,
          icon: Badge(
            isLabelVisible: motor.kuyrukSayisi > 0,
            label: Text('${motor.kuyrukSayisi}'),
            child: Icon(motor.cevrimdisi ? Icons.cloud_off : Icons.sync),
          ),
        );
      },
    );
  }
}

/// Listenin üstünde ince durum şeridi (çevrimdışı, ilk yükleme, hata). Gösterecek bir şey yoksa boş kalır.
class SenkronSeridi extends StatelessWidget {
  const SenkronSeridi({super.key, required this.motor});

  final SenkronMotoru motor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: motor,
      builder: (context, _) {
        final tema = Theme.of(context);
        String? metin;
        IconData ikon = Icons.info_outline;
        Color? renk = tema.colorScheme.secondaryContainer;
        if (motor.ilkYukleme) {
          metin = 'İlk yükleme sürüyor: ${motor.indirilen} talep indirildi';
          ikon = Icons.downloading;
        } else if (motor.cevrimdisi) {
          metin = motor.kuyrukSayisi > 0
              ? 'Çevrimdışı · ${motor.kuyrukSayisi} değişiklik bağlantı gelince gönderilecek'
              : 'Çevrimdışı · son kaydedilen veriler gösteriliyor';
          ikon = Icons.cloud_off;
          renk = tema.colorScheme.tertiaryContainer;
        } else if (motor.sonHata != null) {
          metin = motor.sonHata;
          ikon = Icons.error_outline;
          renk = tema.colorScheme.errorContainer;
        }
        if (metin == null) return const SizedBox.shrink();
        return Material(
          color: renk,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(ikon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(metin, style: tema.textTheme.bodySmall)),
              ],
            ),
          ),
        );
      },
    );
  }
}
