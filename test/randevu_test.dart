import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/program.dart';
import 'package:ozelkalem/veri/randevu.dart';
import 'package:ozelkalem/veri/randevu_deposu.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _r(String adi, DateTime t, {int kat = 1, int durum = 1}) =>
    {
      'katno': kat,
      'durum': durum,
      'adi': adi,
      'unvan': '',
      'telefon': '0532 111 22 33',
      'tarih': programZamanYaz(t),
      'sure_dk': 30,
      'yer': '',
      'notlar': '',
    };

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late RandevuDeposu depo;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = RandevuDeposu(yerel);
  });
  tearDown(() => yerel.kapat());

  test('zaman sekmeleri, sayaçlar ve süzgeçler', () async {
    final bugun = gunBasi(DateTime.now());
    await depo.kaydet(_r('Bugün biri', bugun.add(const Duration(hours: 10))));
    await depo.kaydet(
      _r('Yarın biri', bugun.add(const Duration(days: 1, hours: 9)), kat: 2),
    );
    await depo.kaydet(
      _r('Geçmiş biri', bugun.subtract(const Duration(days: 3)), durum: 2),
    );

    expect((await depo.liste(const RandevuFiltre())).length, 2);
    expect(
      (await depo.liste(const RandevuFiltre(zaman: RandevuZaman.bugun)))
          .single
          .adi,
      'Bugün biri',
    );
    expect(
      (await depo.liste(const RandevuFiltre(zaman: RandevuZaman.gecmis)))
          .single
          .adi,
      'Geçmiş biri',
    );
    final tumu = await depo.liste(
      const RandevuFiltre(zaman: RandevuZaman.tumu, durum: 2),
    );
    expect(tumu.single.adi, 'Geçmiş biri');
    final s = await depo.zamanSayilari();
    expect(s[RandevuZaman.tumu], 3);
    expect(s[RandevuZaman.yaklasan], 2);
    expect(s[RandevuZaman.bugun], 1);
    expect(s[RandevuZaman.gecmis], 1);
    final k = await depo.kategoriSayilari(
      const RandevuFiltre(zaman: RandevuZaman.tumu),
    );
    expect(k[1], 2);
    expect(k[2], 1);
    final ara = await depo.liste(
      const RandevuFiltre(zaman: RandevuZaman.tumu, kelime: 'yarın'),
    );
    expect(ara.single.adi, 'Yarın biri');
  });

  test(
    'kaydet kuyruğa yazar, aynı kayıt birleşir, silme kuyruğa girer',
    () async {
      final id = await depo.kaydet(_r('Ali', DateTime.now()));
      await depo.kaydet(_r('Ali Veli', DateTime.now()), yerelId: id);
      final k = await depo.kuyruk();
      expect(k.length, 1);
      expect(k.single.tur, 'kaydet');

      // sunucuya gitmiş gibi
      await depo.islemBasarili(
        k.single,
        sunucuRandevu: {
          ..._r('Ali Veli', DateTime.now()),
          'no': 77,
          'surum': 5,
          'ekleyen': 1,
          'program_no': 0,
        },
      );
      expect(await depo.kuyrukSayisi(), 0);
      await depo.durumDegistir(id, 3);
      final op = (await depo.kuyruk()).single;
      expect(op.no, 77);
      expect(op.taban, 5);

      await depo.sil(id);
      expect((await depo.kuyruk()).map((e) => e.tur).toList(), ['sil']);
      expect(await depo.sayi(), 0);
    },
  );

  test('sunucudan gelen, gönderilmemiş yerel değişikliği ezmez', () async {
    await depo.sunucudanYaz([
      {..._r('Sunucu', DateTime.now()), 'no': 9, 'surum': 1},
    ], []);
    final id = (await depo.yerelIdNo(9))!;
    await depo.durumDegistir(id, 4);
    await depo.sunucudanYaz([
      {..._r('Sunucu 2', DateTime.now()), 'no': 9, 'surum': 2},
    ], []);
    expect((await depo.getir(id))!.durum, 4);
  });

  test('göreli etiket', () {
    final n = DateTime(2026, 10, 31, 12);
    expect(randevuGoreli(DateTime(2026, 10, 31, 9), n).etiket, 'Bugün');
    expect(randevuGoreli(DateTime(2026, 11, 1, 9), n).etiket, 'Yarın');
    expect(randevuGoreli(DateTime(2026, 11, 4, 9), n).etiket, '4 gün sonra');
    expect(randevuGoreli(DateTime(2026, 10, 30, 9), n).etiket, 'Geçti');
    expect(randevuGoreli(DateTime(2026, 12, 30, 9), n).etiket, '');
  });
}
