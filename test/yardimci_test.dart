import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/yazi_formatlari.dart';
import 'package:ozelkalem/veri/tarih_yardimci.dart';

void main() {
  test('gün etiketleri', () {
    final simdi = DateTime(2026, 10, 30, 14);
    expect(gunEtiketi('2026-10-30', simdi: simdi), 'Bugün');
    expect(gunEtiketi('2026-10-29', simdi: simdi), 'Dün');
    expect(gunEtiketi('2026-10-17', simdi: simdi), '17 Ekim 2026');
    expect(gunEtiketi(null, simdi: simdi), 'Tarihsiz');
    expect(uzunTarih('2026-01-05'), '5 Ocak 2026');
    expect(uzunTarih('0000-00-00'), isNull);
  });

  test('telefon rakamları (WhatsApp biçimi)', () {
    expect(telefonRakamlari('0532 000 00 00'), '905320000000');
    expect(telefonRakamlari('+90 532 000 00 00'), '905320000000');
    expect(telefonRakamlari('5320000000'), '905320000000');
  });

  test('html düz metin ve geri dönüşüm', () {
    expect(
      htmlDuz('<p>Merhaba</p><p>Dünya &amp; ben</p>'),
      'Merhaba\nDünya & ben',
    );
    expect(duzHtml('a<b\nc'), '<p>a&lt;b</p><p>c</p>');
  });
}
