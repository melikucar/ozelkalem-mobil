import 'package:flutter/material.dart';

/// Kurumsal marka sabitleri. Giriş ekranı (web giriş sayfasındaki lacivert + altın) ve makam kartı bunları kullanır;
/// uygulamanın geri kalanı kullanıcının kendi tema tercihini (stil, mod, vurgu rengi) izler.
class Marka {
  static const lacivert = Color(0xFF0C1C2F);
  static const lacivert2 = Color(0xFF14304E);
  static const altin = Color(0xFFDEC290);
  static const altinKoyu = Color(0xFFB8913F);
  static const mavi = Color(0xFF0060F0);
  static const camgobegi = Color(0xFF00E0F0);
  static const logoYazi = Color(0xFF002666);
}

/// Web panelindeki 14 vurgu rengi (themes.css [data-color]) ve görünen adları.
const Map<String, ({String ad, Color renk})> vurguRenkleri = {
  'black': (ad: 'Siyah', renk: Color(0xFF000000)),
  'gray-dark': (ad: 'Koyu gri', renk: Color(0xFF343A40)),
  'gray': (ad: 'Gri', renk: Color(0xFF6C757D)),
  'cyan': (ad: 'Turkuaz', renk: Color(0xFF38B4CD)),
  'teal': (ad: 'Deniz yeşili', renk: Color(0xFF00976A)),
  'green': (ad: 'Yeşil', renk: Color(0xFF00723D)),
  'yellow': (ad: 'Sarı', renk: Color(0xFFFFB400)),
  'orange': (ad: 'Turuncu', renk: Color(0xFFE66900)),
  'red': (ad: 'Kırmızı', renk: Color(0xFFC20013)),
  'pink': (ad: 'Pembe', renk: Color(0xFFC20060)),
  'purple': (ad: 'Mor', renk: Color(0xFF6D3CC7)),
  'indigo': (ad: 'Çivit', renk: Color(0xFF5912CD)),
  'blue': (ad: 'Mavi', renk: Color(0xFF004EC1)),
  'white': (ad: 'Beyaz', renk: Color(0xFFFFFFFF)),
};

const Map<String, String> stilAdlari = {
  'klasik': 'Klasik',
  'kurumsal': 'Kurumsal',
  'cam': 'Modern cam',
};

/// Kullanıcının tema tercihi: web'deki üç bağımsız eksen (stil × mod × renk). Sunucuda yoneticiler.tema_* alanlarında tutulur.
@immutable
class TemaTercihi {
  const TemaTercihi({
    this.mod = 'light',
    this.stil = 'klasik',
    this.renk = 'blue',
  });

  final String mod; // light | dark
  final String stil; // klasik | kurumsal | cam
  final String renk; // vurguRenkleri anahtarı

  bool get koyu => mod == 'dark';

  /// /ben yanıtındaki `yonetici` nesnesinden. Eski "glass" modu = koyu taban + cam stili (web ile aynı dönüşüm).
  factory TemaTercihi.benden(Map? y) {
    var mod = (y?['tema_mode'] ?? 'light').toString();
    var stil = (y?['tema_stil'] ?? 'klasik').toString();
    var renk = (y?['tema_renk'] ?? 'blue').toString();
    if (mod == 'glass') {
      mod = 'dark';
      stil = 'cam';
    }
    if (mod != 'light' && mod != 'dark') mod = 'light';
    if (!stilAdlari.containsKey(stil)) stil = 'klasik';
    if (!vurguRenkleri.containsKey(renk)) renk = 'blue';
    return TemaTercihi(mod: mod, stil: stil, renk: renk);
  }

  TemaTercihi kopya({String? mod, String? stil, String? renk}) => TemaTercihi(
    mod: mod ?? this.mod,
    stil: stil ?? this.stil,
    renk: renk ?? this.renk,
  );

  @override
  bool operator ==(Object other) =>
      other is TemaTercihi &&
      other.mod == mod &&
      other.stil == stil &&
      other.renk == renk;

  @override
  int get hashCode => Object.hash(mod, stil, renk);
}

/// Seçilen stil + mod için yüzey renkleri (web temalar.css değişkenlerinin karşılığı).
class _Yuzey {
  const _Yuzey({
    required this.sayfa,
    required this.yuzey,
    required this.yuzey2,
    required this.metin,
    required this.soluk,
    required this.cizgi,
  });

  final Color sayfa, yuzey, yuzey2, metin, soluk, cizgi;

  static _Yuzey al(String stil, bool koyu) {
    switch (stil) {
      case 'kurumsal':
        return koyu
            ? const _Yuzey(
                sayfa: Color(0xFF14181C),
                yuzey: Color(0xFF1D2227),
                yuzey2: Color(0xFF252B32),
                metin: Color(0xFFE6E9EE),
                soluk: Color(0xFF9AA4B2),
                cizgi: Color(0xFF323A43),
              )
            : const _Yuzey(
                sayfa: Color(0xFFECEFF4),
                yuzey: Color(0xFFFFFFFF),
                yuzey2: Color(0xFFF4F6F9),
                metin: Color(0xFF1F2937),
                soluk: Color(0xFF6B7280),
                cizgi: Color(0xFFD5DBE3),
              );
      case 'cam':
        return koyu
            ? const _Yuzey(
                sayfa: Color(0xFF0A0F1D),
                yuzey: Color(0xFF1B2236),
                yuzey2: Color(0x14FFFFFF),
                metin: Color(0xFFEEF2FA),
                soluk: Color(0xFF9FAAC0),
                cizgi: Color(0x2EFFFFFF),
              )
            : const _Yuzey(
                sayfa: Color(0xFFF4F6FA),
                yuzey: Color(0xFFFAFBFE),
                yuzey2: Color(0x8CFFFFFF),
                metin: Color(0xFF1B2333),
                soluk: Color(0xFF5A6478),
                cizgi: Color(0xBFFFFFFF),
              );
      default: // klasik
        return koyu
            ? const _Yuzey(
                sayfa: Color(0xFF212529),
                yuzey: Color(0xFF2B3035),
                yuzey2: Color(0xFF343A40),
                metin: Color(0xFFF8F9FA),
                soluk: Color(0xFFADB5BD),
                cizgi: Color(0xFF495057),
              )
            : const _Yuzey(
                sayfa: Color(0xFFF2F2F2),
                yuzey: Color(0xFFFFFFFF),
                yuzey2: Color(0xFFE9ECEF),
                metin: Color(0xFF212529),
                soluk: Color(0xFF6C757D),
                cizgi: Color(0xFFCED4DA),
              );
    }
  }
}

/// Vurgu rengini zemine göre okunur hale getirir (ör. koyu modda siyah/koyu gri yerine açık ton; açık modda "beyaz" yerine lacivert).
Color erisilebilirVurgu(String renk, bool koyu) {
  final taban = vurguRenkleri[renk]?.renk ?? vurguRenkleri['blue']!.renk;
  if (renk == 'white') return koyu ? Colors.white : Marka.lacivert2;
  if (koyu && taban.computeLuminance() < 0.14) {
    final h = HSLColor.fromColor(taban);
    return h.withLightness(0.70).withSaturation(h.saturation * 0.6).toColor();
  }
  return taban;
}

Color karistir(Color taban, Color ust, double oran) =>
    Color.lerp(taban, ust, oran)!;

/// "Modern cam" stilinin zemini: vurgu renginden türetilen yumuşak gradyan.
BoxDecoration camZemin(TemaTercihi t) {
  final v = erisilebilirVurgu(t.renk, t.koyu);
  final renkler = t.koyu
      ? [
          karistir(const Color(0xFF101626), v, 0.50),
          karistir(const Color(0xFF0A0F1D), v, 0.22),
          const Color(0xFF0A0F1D),
        ]
      : [
          karistir(Colors.white, v, 0.16),
          karistir(const Color(0xFFF4F6FA), v, 0.26),
          karistir(Colors.white, v, 0.08),
        ];
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: renkler,
    ),
  );
}

/// Kullanıcının tercihinden tam bir Material teması üretir.
ThemeData temaUret(TemaTercihi t) {
  final koyu = t.koyu;
  final y = _Yuzey.al(t.stil, koyu);
  final vurgu = erisilebilirVurgu(t.renk, koyu);
  final onVurgu = vurgu.computeLuminance() > 0.5
      ? const Color(0xFF212529)
      : Colors.white;
  final cam = t.stil == 'cam';

  final sema =
      ColorScheme.fromSeed(
        seedColor: vurgu,
        brightness: koyu ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: vurgu,
        onPrimary: onVurgu,
        surface: y.yuzey,
        onSurface: y.metin,
        onSurfaceVariant: y.soluk,
        outline: y.soluk,
        outlineVariant: y.cizgi,
        surfaceContainerLowest: y.sayfa,
        surfaceContainerLow: y.yuzey,
        surfaceContainer: y.yuzey,
        surfaceContainerHigh: y.yuzey2,
        surfaceContainerHighest: y.yuzey2,
        primaryContainer: karistir(y.yuzey, vurgu, koyu ? 0.28 : 0.16),
        onPrimaryContainer: y.metin,
        secondaryContainer: karistir(y.yuzey, vurgu, koyu ? 0.22 : 0.12),
        onSecondaryContainer: y.metin,
      );

  // Kart yüzeyi: cam stilinde yarı saydam, diğerlerinde düz
  final kartRenk = cam
      ? (koyu ? const Color(0x14FFFFFF) : const Color(0x8CFFFFFF))
      : y.yuzey;
  final kartKenar = switch (t.stil) {
    'kurumsal' => BorderSide(color: y.cizgi),
    'cam' => BorderSide(color: y.cizgi),
    _ => BorderSide.none,
  };
  final kartYaricap = switch (t.stil) {
    'kurumsal' => 8.0,
    'cam' => 18.0,
    _ => 14.0,
  };

  final appBar = switch (t.stil) {
    'kurumsal' => AppBarTheme(
      backgroundColor: y.yuzey,
      foregroundColor: y.metin,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: vurgu, width: 3)),
    ),
    'cam' => AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: y.metin,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    _ => AppBarTheme(
      backgroundColor: vurgu,
      foregroundColor: onVurgu,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  };

  final girdiKenar = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: y.cizgi),
  );

  return _sikiHarf(
    ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: sema,
      brightness: koyu ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: cam ? Colors.transparent : y.sayfa,
      canvasColor: y.yuzey,
      dividerColor: y.cizgi,
      dividerTheme: DividerThemeData(color: y.cizgi, space: 1, thickness: 1),
      appBarTheme: appBar.copyWith(
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: appBar.foregroundColor,
        ),
        systemOverlayStyle: null,
      ),
      cardTheme: CardThemeData(
        color: kartRenk,
        elevation: t.stil == 'klasik' ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kartYaricap),
          side: kartKenar,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: girdiKenar,
        enabledBorder: girdiKenar,
        focusedBorder: girdiKenar.copyWith(
          borderSide: BorderSide(color: vurgu, width: 2),
        ),
        errorBorder: girdiKenar.copyWith(
          borderSide: BorderSide(color: sema.error),
        ),
        focusedErrorBorder: girdiKenar.copyWith(
          borderSide: BorderSide(color: sema.error, width: 2),
        ),
        filled: cam,
        fillColor: cam
            ? (koyu ? const Color(0x14FFFFFF) : const Color(0x99FFFFFF))
            : null,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: vurgu,
          foregroundColor: onVurgu,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: y.metin,
          side: BorderSide(color: y.cizgi),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: vurgu,
        foregroundColor: onVurgu,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: y.cizgi),
        labelStyle: TextStyle(color: y.metin),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cam
            ? (koyu ? const Color(0xFF1B2236) : const Color(0xFFFAFBFE))
            : y.yuzey,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kartYaricap + 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cam
            ? (koyu ? const Color(0xFF1B2236) : const Color(0xFFFAFBFE))
            : y.yuzey,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cam
            ? (koyu ? const Color(0xFF1B2236) : const Color(0xFFFAFBFE))
            : y.yuzey,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cam
            ? (koyu ? const Color(0x99101626) : const Color(0x99FFFFFF))
            : y.yuzey,
        surfaceTintColor: Colors.transparent,
        elevation: t.stil == 'klasik' ? 3 : 0,
        height: 68,
        indicatorColor: vurgu.withValues(alpha: koyu ? 0.28 : 0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 25,
            color: s.contains(WidgetState.selected)
                ? (vurgu.computeLuminance() > 0.5 && !koyu ? y.metin : vurgu)
                : y.soluk,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? y.metin : y.soluk,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      listTileTheme: ListTileThemeData(textColor: y.metin, iconColor: y.soluk),
      textSelectionTheme: TextSelectionThemeData(cursorColor: vurgu),
    ),
  );
}

/// Giriş ekranı için marka teması (kullanıcının tercihi henüz bilinmiyor): web giriş sayfasındaki lacivert + altın.
ThemeData girisTemasi() {
  const zemin = Color(0xFFF4F6F9);
  final sema =
      ColorScheme.fromSeed(
        seedColor: Marka.lacivert2,
        brightness: Brightness.light,
      ).copyWith(
        primary: Marka.lacivert2,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: const Color(0xFF14202E),
        onSurfaceVariant: const Color(0xFF5B6878),
        outlineVariant: const Color(0xFFD9DFE7),
      );
  final kenar = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Color(0xFFBCC6D2)),
  );
  return _sikiHarf(
    ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: sema,
      scaffoldBackgroundColor: zemin,
      inputDecorationTheme: InputDecorationTheme(
        border: kenar,
        enabledBorder: kenar,
        focusedBorder: kenar.copyWith(
          borderSide: const BorderSide(color: Marka.altinKoyu, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Marka.lacivert2,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Marka.altinKoyu,
      ),
    ),
  );
}

/// Tüm yazı stillerinde harf aralığını biraz daraltır (Material'in varsayılan genişletmesini azaltır).
ThemeData _sikiHarf(ThemeData t) {
  TextStyle? d(TextStyle? s) =>
      s?.copyWith(letterSpacing: (s.letterSpacing ?? 0) - 0.3);
  final x = t.textTheme;
  return t.copyWith(
    textTheme: x.copyWith(
      displayLarge: d(x.displayLarge),
      displayMedium: d(x.displayMedium),
      displaySmall: d(x.displaySmall),
      headlineLarge: d(x.headlineLarge),
      headlineMedium: d(x.headlineMedium),
      headlineSmall: d(x.headlineSmall),
      titleLarge: d(x.titleLarge),
      titleMedium: d(x.titleMedium),
      titleSmall: d(x.titleSmall),
      bodyLarge: d(x.bodyLarge),
      bodyMedium: d(x.bodyMedium),
      bodySmall: d(x.bodySmall),
      labelLarge: d(x.labelLarge),
      labelMedium: d(x.labelMedium),
      labelSmall: d(x.labelSmall),
    ),
  );
}
