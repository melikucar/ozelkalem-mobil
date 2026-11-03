import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Esnemeyi kapatır: kaydırma listelerin başında/sonunda hiçbir şeyi uzatmaz ya da esnetmez (Android 12+ "stretch" etkisi
/// ve iOS yaylanması kapalı); kenarda içerik olduğu gibi durur.
class EsnemesizKaydirma extends MaterialScrollBehavior {
  const EsnemesizKaydirma();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}
