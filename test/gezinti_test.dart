import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/diger/premium_gezinti.dart';

void main() {
  const adlar = [
    'Ana sayfa',
    'Talepler',
    'Programlar',
    'Randevular',
    'Faaliyetler',
    'Rehber',
    'Yazışmalar',
    'Raporlar',
    'Yasama',
  ];
  final ogeler = [
    for (final a in adlar) GezintiOgesi(a, Icons.circle_outlined, Icons.circle),
  ];

  for (final genislik in [320.0, 360.0, 411.0]) {
    testWidgets(
      'üç alanlı dock; modüller paneli tüm modülleri ve bildirimi açar (${genislik.toInt()} dp)',
      (tester) async {
        tester.view.physicalSize = Size(genislik * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        var secili = 0;
        var eylem = '';
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (c, set) => Scaffold(
                bottomNavigationBar: PremiumGezinti(
                  ogeler: ogeler,
                  secili: secili,
                  sec: (i) => set(() => secili = i),
                  stil: 'klasik',
                  panelEylemleri: [
                    GezintiEylemi(
                      ad: 'Bildirimler',
                      ikon: Icons.notifications_none,
                      tikla: (_) => eylem = 'bildirim',
                    ),
                  ],
                  eylemler: [
                    GezintiEylemi(
                      ad: 'Profil',
                      ikon: Icons.person,
                      tikla: (k) => eylem = 'profil',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SingleChildScrollView), findsNothing);
        // yalnız: ana sayfa (adsız), modüller düğmesi, profil
        expect(find.text('Ana sayfa'), findsNothing);
        expect(find.byKey(const ValueKey('modul_dugme_simge')), findsOneWidget);
        expect(find.byIcon(Icons.person), findsOneWidget);

        // panel: 8 modül + bildirimler
        await tester.tap(find.byKey(const ValueKey('modul_dugme_simge')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));
        for (final a in adlar.skip(1)) {
          expect(find.text(a), findsOneWidget, reason: a);
        }
        expect(find.text('Bildirimler'), findsOneWidget);

        await tester.tap(find.text('Bildirimler'));
        await tester.pumpAndSettle();
        expect(eylem, 'bildirim');
        expect(find.text('Talepler'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('modul_dugme_simge')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));
        await tester.tap(find.text('Yasama'));
        await tester.pumpAndSettle();
        expect(secili, 8);
        // modül seçilince ortadaki düğme değişmez (adı/simgesi aynı kalır)
        expect(find.text('Yasama'), findsNothing);
        expect(find.byKey(const ValueKey('modul_dugme_simge')), findsOneWidget);

        // ana sayfaya dön
        // modüldeyken profil düğmesi alt çubukta çalışır
        await tester.tap(find.byIcon(Icons.person));
        expect(eylem, 'profil');

        await tester.tap(find.byIcon(Icons.circle_outlined).first);
        await tester.pumpAndSettle();
        expect(secili, 0);

        // ana sayfadayken alt çubuktaki ana sayfa ve profil düğmeleri gizlenir (profil hero'da)
        eylem = '';
        await tester.tap(find.byIcon(Icons.person), warnIfMissed: false);
        expect(eylem, '');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
