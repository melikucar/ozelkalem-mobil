import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/api/oturum.dart';
import 'package:ozelkalem/api/token_deposu.dart';
import 'package:ozelkalem/diger/giris_ekrani.dart';

void main() {
  testWidgets('Giriş ekranı doğrulama uyarıları gösterir', (tester) async {
    final oturum = Oturum(TokenDeposu());
    await tester.pumpWidget(MaterialApp(home: GirisEkrani(oturum: oturum)));
    await tester.pump(
      const Duration(seconds: 4),
    ); // açılış animasyonu + ışıltı zamanlayıcısı

    final dugme = find.text('Sisteme Giriş');
    expect(dugme, findsOneWidget);
    await tester.ensureVisible(dugme);
    await tester.tap(dugme);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('11 haneli TCKN girin'), findsOneWidget);
    expect(find.text('Şifrenizi girin'), findsOneWidget);
  });
}
