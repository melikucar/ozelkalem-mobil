import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/tbmm.dart';
import 'package:ozelkalem/veri/tbmm_deposu.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _gun(int once) =>
    tbmmTarihYaz(DateTime.now().subtract(Duration(days: once)));

Map<String, dynamic> _sunucu(
  int no,
  int tablo,
  String adi,
  int surum, {
  String? tarih,
}) => {
  'no': no,
  'surum': surum,
  'tablo': tablo,
  'adi': adi,
  'tarih': tarih ?? _gun(1),
  'icerik': '<p>Sunucu metni</p>',
  'notlar': 'Not',
  'ekleyen': 1,
  'ek': 0,
};

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late TbmmDeposu depo;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = TbmmDeposu(yerel);
  });
  tearDown(() => yerel.kapat());

  test(
    'yeni kayıt kuyruğa düz metinle yazılır; yerelde paragraf HTML görünür',
    () async {
      final id = await depo.kaydet({
        'tablo': 2,
        'adi': 'Yazılı Soru',
        'tarih': '2026-10-30',
        'notlar': 'Not',
        'icerik': 'Birinci\nİkinci <b>',
      });
      final t = (await depo.getir(id))!;
      expect(t.icerik, '<p>Birinci</p><p>İkinci &lt;b&gt;</p>');
      expect(t.tablo, 2);
      expect(t.bekleyen, true);
      final op = (await depo.kuyruk()).single;
      expect(op.no, isNull);
      expect(op.govde['icerik'], 'Birinci\nİkinci <b>');
      expect(op.govde['tablo'], 2);
      expect(op.govde['tarih'], '2026-10-30');
      expect(
        (await depo.liste(const TbmmFiltre(kelime: 'yazili soru'))).length,
        1,
      );
    },
  );

  test(
    'düzenleme: içerik değişmediyse gönderilmez; bekleyen işleme birleşir',
    () async {
      await depo.sunucudanYaz([_sunucu(7, 1, 'Teklif', 4)], []);
      final id = (await depo.noIle(7))!.yerelId!;
      await depo.kaydet({
        'tablo': 1,
        'adi': 'Teklif 2',
        'tarih': _gun(1),
        'notlar': 'Yeni not',
      }, yerelId: id);
      var op = (await depo.kuyruk()).single;
      expect(op.no, 7);
      expect(op.taban, 4);
      expect(op.govde.containsKey('icerik'), false);
      expect((await depo.getir(id))!.icerik, '<p>Sunucu metni</p>');
      await depo.kaydet({
        'tablo': 3,
        'adi': 'Teklif 2',
        'tarih': _gun(1),
        'notlar': 'Yeni not',
        'icerik': 'Yeni metin',
      }, yerelId: id);
      op = (await depo.kuyruk()).single;
      expect(op.govde['tablo'], 3);
      expect(op.govde['icerik'], 'Yeni metin');
    },
  );

  test('tür süzgeci, arama, tür sayıları ve özet', () async {
    final n = DateTime.now();
    final buAyBasi = tbmmTarihYaz(DateTime(n.year, n.month, 1));
    await depo.sunucudanYaz([
      _sunucu(1, 1, 'Kanun A', 1, tarih: buAyBasi),
      _sunucu(2, 1, 'Kanun B', 1, tarih: '2020-01-05'),
      _sunucu(3, 2, 'Soru C', 1, tarih: '2020-02-05'),
    ], []);
    expect((await depo.liste(const TbmmFiltre())).length, 3);
    expect((await depo.liste(const TbmmFiltre(tablo: 1))).length, 2);
    expect((await depo.liste(const TbmmFiltre(kelime: 'soru c'))).single.no, 3);
    expect(
      (await depo.liste(const TbmmFiltre(kelime: 'sunucu metni'))).length,
      3,
    );
    expect(await depo.turSayilari(), {1: 2, 2: 1});
    final o = await depo.ozet(1);
    expect(o.toplam, 2);
    expect(o.buAy, 1);
    expect(o.buYil >= 1, true);
    expect(o.son, buAyBasi);
    expect((await depo.ozet(0)).toplam, 3);
    expect((await depo.ozet(9)).toplam, 0);
  });

  test(
    'sunucudan gelen yerel değişikliği ezmez; silme, uzlaştırma ve çakışma',
    () async {
      await depo.sunucudanYaz([_sunucu(9, 1, 'Sunucu', 1)], []);
      final id = (await depo.noIle(9))!.yerelId!;
      await depo.kaydet({
        'tablo': 1,
        'adi': 'Yerel',
        'tarih': _gun(1),
      }, yerelId: id);
      await depo.sunucudanYaz([_sunucu(9, 1, 'Sunucu 2', 2)], []);
      expect((await depo.getir(id))!.adi, 'Yerel');

      final op = (await depo.kuyruk()).single;
      await depo.islemSorunlu(
        op,
        'cakisma',
        'x',
        sunucu: _sunucu(9, 1, 'Başkası', 5),
      );
      await depo.cakismaBenimkiniGonder((await depo.sorunlular())[id]!);
      expect((await depo.kuyruk()).single.taban, 5);
      await depo.islemSorunlu(
        (await depo.kuyruk()).single,
        'cakisma',
        'x',
        sunucu: _sunucu(9, 1, 'Başkası', 6),
      );
      await depo.cakismaSunucuyuAl((await depo.sorunlular())[id]!);
      expect((await depo.getir(id))!.adi, 'Başkası');
      expect(await depo.kuyrukSayisi(), 0);

      await depo.sil(id);
      expect((await depo.kuyruk()).map((e) => e.tur).toList(), ['sil']);
      expect(await depo.sayi(), 0);

      await depo.sunucudanYaz([
        _sunucu(11, 1, 'A', 1),
        _sunucu(12, 1, 'B', 1),
      ], []);
      expect(await depo.uzlastir({11}), 1);
      expect(await depo.noIle(12), isNull);
    },
  );

  test('ek dosya işlemleri kuyruğa yazılır; ayrıntı önbelleği ek sayısını günceller', () async {
    await depo.sunucudanYaz([_sunucu(20, 4, 'Önerge', 1)], []);
    final id = (await depo.noIle(20))!.yerelId!;
    await depo.dosyaEkle(id, yol: '/tmp/a.pdf', ad: 'a.pdf', boyut: 10);
    await depo.sunucuDosyasiniSil(id, 20, '20-eski.pdf');
    final d = await depo.dosyaIslemleri(id);
    expect(d.map((e) => e.tur).toList(), ['dosya', 'dosya_sil']);
    expect(d.first.no, 20);
    await depo.dosyaIsleminiIptalEt(d.first);
    expect((await depo.dosyaIslemleri(id)).length, 1);

    await depo.ekYaz(20, {
      'dosyalar': [
        {'ad': '20-x.pdf'},
        {'ad': '20-y.pdf'},
      ],
    });
    expect((await depo.getir(id))!.ek, 2);
    expect((await depo.ekOku(20))!['dosyalar'], hasLength(2));
  });
}
