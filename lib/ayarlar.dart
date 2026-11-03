//import 'package:flutter/foundation.dart';

/// API adresi, derleme türüne göre seçilir:
///  - release (`flutter build apk --release`, dağıtım/render): CANLI sunucu.
///  - debug / profile (`flutter run`, `flutter build apk --debug`): emülatörün bilgisayardaki yerel TEST sunucusu
///    (bkz. tools/test/ortam.sh; emülatörde 10.0.2.2 bilgisayarın localhost'udur).
/// Gerekirse her ikisi de zorlanabilir: `--dart-define=API_TABAN=https://.../api/v1`
/// (ör. gerçek telefonda debug çalıştırıp canlıya bağlanmak için).
/*
const String canliApiTaban = 'https://v7.ozelkalemotomasyonu.com/api/v1';
const String yerelApiTaban = 'http://10.0.2.2:8099/api/v1';
const String apiTaban = String.fromEnvironment(
  'API_TABAN',
  defaultValue: kReleaseMode ? canliApiTaban : yerelApiTaban,
);
*/
const String apiTaban = 'https://v7.ozelkalemotomasyonu.com/api/v1';

/// Uygulama sürümü pubspec.yaml'dan (package_info_plus) okunur; burada yedek değer.
const String yedekSurum = '7.0.0';

/// İlk yüklemede yalnızca son N aya ait talepler indirilir (0 = hepsi; önerilen: bazı makamların talepleri eskidir).
/// Kayıtlar en yeniden eskiye iner, liste hemen dolmaya başlar.
const int ilkYuklemeAy = 0;

/// Uygulama açıkken otomatik senkron aralığı.
const Duration senkronAraligi = Duration(seconds: 60);
