import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Uygulamanın tüm bildirimleri bu servisten geçer: uygulama açıkken üstten kayan bir toast, arka plandayken / ekran kilitliyken
/// sistem bildirimi (kilit ekranında da görünür). Bildirim izni uygulama ilk açıldığında istenir.
class BildirimServisi with WidgetsBindingObserver {
  BildirimServisi._();

  static final BildirimServisi ornek = BildirimServisi._();

  static const _kanal = AndroidNotificationChannel(
    'genel',
    'Genel bildirimler',
    description: 'Talep, program, randevu ve sistem bildirimleri',
    importance: Importance.high,
  );

  final _eklenti = FlutterLocalNotificationsPlugin();
  bool _hazir = false;
  bool _destekli = false;
  AppLifecycleState _durum = AppLifecycleState.resumed;
  int _no = 0;

  /// Uygulama açıkken gösterilecek toast (null: yok).
  final ValueNotifier<BildirimIcerigi?> toast = ValueNotifier(null);

  bool get _onPlanda => _durum == AppLifecycleState.resumed;

  /// Eklentiyi kurar ve izni ister. Test/masaüstü gibi desteklenmeyen ortamlarda sessizce geçer.
  Future<void> baslat() async {
    if (_hazir) return;
    _hazir = true;
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    _destekli = true;
    try {
      await _eklenti.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await _eklenti
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_kanal);
      await izinIste();
    } catch (_) {
      _destekli = false;
    }
  }

  /// Bildirim iznini ister (Android 13+ ve iOS'ta sistem penceresi açılır). İzin verildiyse true.
  Future<bool> izinIste() async {
    if (!_destekli) return false;
    try {
      if (Platform.isAndroid) {
        final a = _eklenti
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (await a?.areNotificationsEnabled() ?? false) return true;
        return await a?.requestNotificationsPermission() ?? false;
      }
      return await _eklenti
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Bildirim gösterir: uygulama açıksa üstten toast, değilse sistem bildirimi.
  Future<void> goster(String baslik, String govde) async {
    if (_onPlanda) {
      HapticFeedback.mediumImpact();
      toast.value = BildirimIcerigi(baslik, govde, ++_no);
      return;
    }
    if (!_destekli) return;
    try {
      await _eklenti.show(
        id: ++_no,
        title: baslik,
        body: govde,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'genel',
            'Genel bildirimler',
            channelDescription:
                'Talep, program, randevu ve sistem bildirimleri',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            styleInformation: BigTextStyleInformation(''),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _durum = state;
}

class BildirimIcerigi {
  const BildirimIcerigi(this.baslik, this.govde, this.no);

  final String baslik;
  final String govde;
  final int no;
}
