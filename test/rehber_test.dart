import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/yazi_formatlari.dart';
import 'package:ozelkalem/veri/program.dart';
import 'package:ozelkalem/veri/rehber.dart';
import 'package:ozelkalem/veri/rehber_deposu.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _k(
  String adi, {
  String cep = '',
  int kat = 1,
  bool kara = false,
  String dogum = '',
}) => {
  'katno': kat,
  'adi': adi,
  'unvan': '',
  'cep1': cep,
  'cep2': '',
  'is1': '',
  'isd1': '',
  'is2': '',
  'isd2': '',
  'faks': '',
  'email': '',
  'adres': '',
  'notu': '',
  'dogum': dogum,
  'kara': kara,
};

Map<String, Object?> _g(
  String adi,
  DateTime t, {
  int d1 = 1,
  String tel = '',
}) => {
  'adi': adi,
  'unvan': '',
  'tel1': tel,
  'dah1': '',
  'tel2': '',
  'dah2': '',
  'konu': 'Konu',
  'd1': d1,
  'd2': 0,
  't1': programZamanYaz(t),
  't2': '',
  'notum': '',
};

Map<String, dynamic> _sunucuKisi(String ad, int surum) => {
  'no': 9,
  'surum': surum,
  'katno': 1,
  'adi': ad,
  'unvan': '',
  'cep1': '',
  'cep2': '',
  'is1': '',
  'isd1': '',
  'is2': '',
  'isd2': '',
  'faks': '',
  'email': '',
  'adres': '',
  'notu': '',
  'dogum': '',
  'kara': false,
};

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late RehberDeposu depo;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = RehberDeposu(yerel);
  });
  tearDown(() => yerel.kapat());

  test('Türkçe sıralama anahtarı ve ilk harf', () {
    final adlar = [
      'Zeynep',
      'Çelik',
      'Ahmet',
      'Işık',
      'Hasan',
      'İbrahim',
      'Ömer',
      'Orhan',
      'Şahin',
      'Sema',
    ];
    adlar.sort((a, b) => siraAnahtari(a).compareTo(siraAnahtari(b)));
    expect(adlar, [
      'Ahmet',
      'Çelik',
      'Hasan',
      'Işık',
      'İbrahim',
      'Orhan',
      'Ömer',
      'Sema',
      'Şahin',
      'Zeynep',
    ]);
    expect(ilkHarf('işık'), 'İ');
    expect(ilkHarf('ışık'), 'I');
    expect(ilkHarf('7. Kolordu'), '0-9');
    expect(ilkHarf('  '), '#');
    expect(ilkHarf('@x'), '#');
  });

  test('doğum günü hesabı', () {
    final k = Kisi({'dogum': '1990-11-03'});
    final d = k.sonrakiDogumGunu(DateTime(2026, 10, 31, 15))!;
    expect(d.kalan, 3);
    expect(d.yas, 36);
    final bugun = Kisi({'dogum': '1980-10-31'})
        .sonrakiDogumGunu(DateTime(2026, 10, 31))!;
    expect(bugun.kalan, 0);
    final gecmis = Kisi({'dogum': '1980-10-30'})
        .sonrakiDogumGunu(DateTime(2026, 10, 31))!;
    expect(gecmis.tarih.year, 2027);
    expect(Kisi({'dogum': ''}).sonrakiDogumGunu(), isNull);
  });

  test('kişi listesi: sıralama, harf, arama (telefon dahil), tekrar kayıtlar tek görünür', () async {
    await depo.kisiKaydet(_k('Çelik Ali', cep: '0532 111 22 33'));
    await depo.kisiKaydet(_k('Ahmet Yılmaz', cep: '0533 444 55 66', kat: 2));
    await depo.kisiKaydet(_k('Ahmet Yılmaz', cep: '0533 444 55 66', kat: 2));
    await depo.kisiKaydet(_k('Zeynep Kaya', kara: true));

    final liste = await depo.kisiListe(const KisiFiltre());
    expect(liste.map((e) => e.adi).toList(), [
      'Ahmet Yılmaz',
      'Çelik Ali',
      'Zeynep Kaya',
    ]);
    expect(await depo.kisiSayisi(), 3);
    expect(
      (await depo.kisiListe(const KisiFiltre(harf: 'Ç'))).single.adi,
      'Çelik Ali',
    );
    expect(
      (await depo.kisiListe(const KisiFiltre(kelime: 'celik'))).single.adi,
      'Çelik Ali',
    );
    expect(
      (await depo.kisiListe(const KisiFiltre(kelime: '5334445566'))).single.adi,
      'Ahmet Yılmaz',
    );
    expect((await depo.kisiListe(const KisiFiltre(katno: 2))).length, 1);
    expect(
      (await depo.kisiListe(const KisiFiltre(karaListe: true))).single.adi,
      'Zeynep Kaya',
    );
    final h = await depo.harfSayilari(const KisiFiltre());
    expect(h['A'], 1);
    expect(h['Ç'], 1);
    expect(await depo.karaSayisi(), 1);
    expect((await depo.kisiAra('zey')).single.adi, 'Zeynep Kaya');
  });

  test('kişi kaydı kuyruğa yazılır, birleşir; kara liste değişimi tüm alanları korur', () async {
    final id = await depo.kisiKaydet(_k('Ali', cep: '0532 000 00 00'));
    await depo.kisiKaydet({'adi': 'Ali Veli'}, yerelId: id);
    final op = (await depo.kuyruk(RehberVarlik.kisi)).single;
    expect(op.govde['adi'], 'Ali Veli');
    expect(op.govde['cep1'], '0532 000 00 00');

    await depo.islemBasarili(
      RehberVarlik.kisi,
      op,
      sunucu: {
        ..._sunucuKisi('Ali Veli', 3),
        'no': 42,
        'cep1': '0532 000 00 00',
      },
    );
    await depo.karaDegistir(id, true);
    final op2 = (await depo.kuyruk(RehberVarlik.kisi)).single;
    expect(op2.no, 42);
    expect(op2.taban, 3);
    expect(op2.govde['kara'], 1);
    expect(op2.govde['cep1'], '0532 000 00 00');
    expect((await depo.kisiGetir(id))!.kara, true);

    await depo.kisiSil(id);
    expect((await depo.kuyruk(RehberVarlik.kisi)).map((e) => e.tur).toList(), [
      'sil',
    ]);
  });

  test('görüşme listesi, süzgeçler, özet ve kişiye göre geçmiş', () async {
    final n = DateTime.now();
    await depo.gorusmeKaydet(_g('Ali Veli', n, d1: 2, tel: '0532 111 22 33'));
    await depo.gorusmeKaydet(
      _g(
        'Ali Veli',
        n.subtract(const Duration(days: 3)),
        tel: '0532 111 22 33',
      ),
    );
    await depo.gorusmeKaydet(
      _g('Ayşe', n.subtract(const Duration(days: 40)), d1: 3),
    );

    expect((await depo.gorusmeListe(const GorusmeFiltre())).length, 3);
    expect(
      (await depo.gorusmeListe(const GorusmeFiltre(durum: 3))).single.adi,
      'Ayşe',
    );
    expect(
      (await depo.gorusmeListe(const GorusmeFiltre(donem: GorusmeDonemi.son7)))
          .length,
      2,
    );
    expect(
      (await depo.gorusmeListe(const GorusmeFiltre(kelime: '5321112233')))
          .length,
      2,
    );
    final o = await depo.gorusmeOzeti();
    expect(o.toplam, 3);
    expect(o.bugun, 1);
    expect(o.ulasilamayan, 1);

    final ilk = (await depo.gorusmeListe(const GorusmeFiltre())).first;
    expect((await depo.oncekiGorusmeler(ilk)).length, 1);
    expect(ilk.ulasilamadi, true);
    final ds = await depo.durumSayilari(const GorusmeFiltre());
    expect(ds[2], 1);
    expect(ds[1], 1);
  });

  test('sunucudan gelen, gönderilmemiş yerel değişikliği ezmez', () async {
    await depo.sunucudanYaz(RehberVarlik.kisi, [_sunucuKisi('Sunucu', 1)], []);
    final id = (await depo.kisiYerelIdNo(9))!;
    await depo.kisiKaydet({'adi': 'Yerel'}, yerelId: id);
    await depo.sunucudanYaz(RehberVarlik.kisi, [
      _sunucuKisi('Sunucu 2', 2),
    ], []);
    expect((await depo.kisiGetir(id))!.adi, 'Yerel');
  });
}
