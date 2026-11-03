import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/faaliyet.dart';
import 'package:ozelkalem/veri/faaliyet_deposu.dart';
import 'package:ozelkalem/veri/program.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _f(String adi, DateTime t, {int kat = 1, int yer = 1}) => {
  'adi': adi,
  'katno': kat,
  'yer': yer,
  'tarih': programZamanYaz(t),
  'icerik': 'Birinci satır\nİkinci <satır>',
  'haberler': '',
};

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late FaaliyetDeposu depo;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = FaaliyetDeposu(yerel);
  });
  tearDown(() => yerel.kapat());

  test('düz metin paragraf HTML\'ine çevrilir ve kaçışlanır', () {
    expect(duzdenHtml('Bir\nİki <b>'), '<p>Bir</p><p>İki &lt;b&gt;</p>');
    expect(duzdenHtml('  '), '');
  });

  test('liste süzgeçleri, arama ve sayfalama', () async {
    final n = DateTime.now();
    await depo.kaydet(_f('Çankaya ziyareti', n));
    await depo.kaydet(
      _f(
        'Valilik toplantısı',
        n.subtract(const Duration(days: 40)),
        kat: 2,
        yer: 2,
      ),
    );
    await depo.kaydet(
      _f('Okul açılışı', n.subtract(const Duration(days: 5)), kat: 2),
    );

    final hepsi = await depo.liste(const FaaliyetFiltre());
    expect(hepsi.map((e) => e.adi).toList(), [
      'Çankaya ziyareti',
      'Okul açılışı',
      'Valilik toplantısı',
    ]);
    expect((await depo.liste(const FaaliyetFiltre(katno: 2))).length, 2);
    expect(
      (await depo.liste(const FaaliyetFiltre(yer: 2))).single.adi,
      'Valilik toplantısı',
    );
    expect(
      (await depo.liste(const FaaliyetFiltre(kelime: 'cankaya'))).single.adi,
      'Çankaya ziyareti',
    );
    expect(
      (await depo.liste(
        const FaaliyetFiltre(),
        limit: 1,
        offset: 1,
      )).single.adi,
      'Okul açılışı',
    );
    expect(
      await depo.sonucSayisi(
        FaaliyetFiltre(bas: n.subtract(const Duration(days: 10))),
      ),
      2,
    );
    expect(hepsi.first.icerikDuz, 'Birinci satır\nİkinci <satır>');
  });

  test('kaydet kuyruğa yazar, sonra düzenleme taban sürümü taşır', () async {
    final id = await depo.kaydet(_f('Ali', DateTime.now()));
    await depo.kaydet({'adi': 'Ali Veli'}, yerelId: id);
    final k = await depo.kuyruk();
    expect(k.length, 1);
    expect(k.single.govde['adi'], 'Ali Veli');
    expect(k.single.govde['icerik'], 'Birinci satır\nİkinci <satır>');

    await depo.islemBasarili(
      k.single,
      sunucuFaaliyet: {
        'no': 55,
        'surum': 9,
        'katno': 1,
        'yer': 1,
        'adi': 'Ali Veli',
        'tarih': programZamanYaz(DateTime.now()),
        'icerik': '<p>x</p>',
        'notlar': '',
        'haberler': '',
        'ekleyen': 1,
      },
    );
    // yalnızca adı değiştir: içerik gönderilmez (biçim korunur)
    await depo.kaydet({'adi': 'Ali Veli 2'}, yerelId: id);
    final op = (await depo.kuyruk()).single;
    expect(op.no, 55);
    expect(op.taban, 9);
    expect(op.govde.containsKey('icerik'), false);
    expect((await depo.getir(id))!.icerik, '<p>x</p>');

    await depo.sil(id);
    expect((await depo.kuyruk()).map((e) => e.tur).toList(), ['sil']);
  });

  test('sunucudan gelen, gönderilmemiş yerel değişikliği ezmez; kitapçık sayfaları sırayla gelir', () async {
    final t = programZamanYaz(DateTime.now());
    Map<String, dynamic> s(int no, String adi, [int sv = 1]) => {
      'no': no,
      'surum': sv,
      'katno': 1,
      'yer': 1,
      'adi': adi,
      'tarih': t,
      'icerik': '<p>$adi</p>',
      'notlar': '',
      'haberler': 'https://a.com@https://b.com',
      'ekleyen': 1,
    };
    await depo.sunucudanYaz([s(1, 'Bir'), s(2, 'İki'), s(3, 'Üç')], []);
    final id = (await depo.yerelIdNo(2))!;
    await depo.kaydet({'adi': 'İki (yerel)'}, yerelId: id);
    await depo.sunucudanYaz([s(2, 'İki sunucu', 2)], []);
    expect((await depo.getir(id))!.adi, 'İki (yerel)');
    expect((await depo.numaralarla([3, 1, 99])).map((e) => e.no).toList(), [
      3,
      1,
    ]);
    expect((await depo.getir(id))!.haberler, [
      'https://a.com',
      'https://b.com',
    ]);
  });
}
