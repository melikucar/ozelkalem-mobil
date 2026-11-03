import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/program.dart';
import 'package:ozelkalem/veri/yazisma.dart';
import 'package:ozelkalem/veri/yazisma_deposu.dart';
import 'package:ozelkalem/veri/yazisma_sablon.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _y(
  String kisi, {
  String talepEden = '',
  String talepAdi = '',
  int ekleyen = 0,
}) => {
  'kisi': kisi,
  'unvan': 'Bakan',
  'talep_eden': talepEden,
  'talep_adi': talepAdi,
  'logo': true,
  'imza': true,
  'imza_unvan': true,
  'imza_unvan_2': false,
  'alt_yazi': true,
  'ekleyen': ekleyen,
};

Map<String, dynamic> _sunucu(
  int no,
  String kisi,
  int surum, {
  String tarih = '2026-10-01 10:00:00',
}) => {
  'no': no,
  'surum': surum,
  'talep_eden': '',
  'talep_adi': '',
  'kisi': kisi,
  'unvan': '',
  'icerik': '<p>Sunucu metni</p>',
  'tarih': tarih,
  'logo': 1,
  'imza': 1,
  'imza_unvan': 1,
  'imza_unvan_2': 0,
  'alt_yazi': 0,
  'ekleyen': 1,
};

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late YazismaDeposu depo;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = YazismaDeposu(yerel);
  });
  tearDown(() => yerel.kapat());

  test('talep numarası ve ilgili kişi', () {
    expect(talepNumarasi('203048'), true);
    expect(talepNumarasi('0'), false);
    expect(talepNumarasi('Kayıtsız'), false);
    final bagli = Yazisma({'talep_eden': '12', 'talep_adi': 'Ali'});
    expect(bagli.talepBagli, true);
    expect(bagli.ilgili, 'Ali');
    final serbest = Yazisma({'talep_eden': 'Veli', 'talep_adi': 'Veli'});
    expect(serbest.talepBagli, false);
    expect(serbest.ilgili, 'Veli');
  });

  test('şablon: etiketler, tahmin edilen boşluklar, doldurulamayanlar', () {
    final s = YazismaSablonMotoru.uygula(
      '{{AD_SOYAD}} (T.C. Kimlik No: ........) için\nTel: .......... ve ........ tarihinde',
      {'AD_SOYAD': 'ALİ VELİ', 'TCKN': '12345678901', 'TELEFON': '0532'},
    );
    expect(s.metin.contains('ALİ VELİ (T.C. Kimlik No: 12345678901)'), true);
    expect(s.metin.contains('Tel: 0532'), true);
    expect(s.bos, 1); // MULAKAT_TARIHI verisi yok
    expect(YazismaSablonMotoru.kalanBosluk(s.metin), 1);
    final bos = YazismaSablonMotoru.uygula('Sayın {{AD_SOYAD}}', {});
    expect(bos.bos, 1);
    expect(bos.metin, 'Sayın {{AD_SOYAD}}');
  });

  test('hitap: makama göre Sayın ... ve Bakanlığınız ifadeleri düzelir', () {
    expect(
      YazismaSablonMotoru.hitapTuru('Ahmet Yılmaz', 'Adalet Bakanı'),
      'bakan',
    );
    expect(YazismaSablonMotoru.hitapTuru('Emniyet', 'Genel Müdür'), 'genelmd');
    expect(YazismaSablonMotoru.hitapTuru('Ali', 'Milletvekili'), 'yetkili');
    expect(
      YazismaSablonMotoru.hitapDonustur(
        'Sayın Bakanım; Bakanlığınıza, Bakanlığınızdan',
        'genelmd',
      ),
      'Sayın Genel Müdürüm; Genel Müdürlüğünüze, Genel Müdürlüğünüzden',
    );
    expect(
      YazismaSablonMotoru.hitapDonustur(
        'Sayın Bakanım; Bakanlığınıza',
        'bakan',
      ),
      'Sayın Bakanım; Bakanlığınıza',
    );
    expect(
      YazismaSablonMotoru.hitapDonustur('Sayın Bakanım;', 'yetkili'),
      'Sayın Yetkili;',
    );
  });

  test(
    'yeni yazı kuyruğa düz metinle yazılır; listede paragraf HTML görünür',
    () async {
      final id = await depo.kaydet(
        _y('Ahmet Yılmaz', talepEden: '5', talepAdi: 'Ali Veli'),
        metin: 'Birinci\nİkinci <b>',
      );
      final y = (await depo.getir(id))!;
      expect(y.icerik, '<p>Birinci</p><p>İkinci &lt;b&gt;</p>');
      expect(y.bekleyen, true);
      expect(y.logo, true);
      expect(y.imzaUnvan2, false);
      final op = (await depo.kuyruk()).single;
      expect(op.no, isNull);
      expect(op.govde['icerik'], 'Birinci\nİkinci <b>');
      expect(op.govde['icerik_duz'], 1);
      expect(op.govde['imza_unvan_2'], 0);
      expect(op.govde['talep_eden'], '5');
      expect(
        (await depo.liste(const YazismaFiltre(kelime: 'ali veli'))).length,
        1,
      );
    },
  );

  test('düzenleme: metin değişmediyse içerik gönderilmez; bekleyen işleme birleşir', () async {
    await depo.sunucudanYaz([_sunucu(7, 'Mehmet', 4)], []);
    final id = (await depo.noIle(7))!.yerelId!;
    await depo.kaydet({'kisi': 'Mehmet Kaya'}, yerelId: id);
    var op = (await depo.kuyruk()).single;
    expect(op.no, 7);
    expect(op.taban, 4);
    expect(op.govde.containsKey('icerik'), false);
    expect(op.govde['kisi'], 'Mehmet Kaya');
    expect((await depo.getir(id))!.icerik, '<p>Sunucu metni</p>');

    await depo.kaydet({'unvan': 'Müdür'}, yerelId: id, metin: 'Yeni metin');
    op = (await depo.kuyruk()).single; // aynı işlem, birleşti
    expect(op.govde['kisi'], 'Mehmet Kaya');
    expect(op.govde['unvan'], 'Müdür');
    expect(op.govde['icerik'], 'Yeni metin');
    expect(op.govde['icerik_duz'], 1);
  });

  test('süzgeçler: dönem, kaydeden, kişi, arama; en çok yazılanlar', () async {
    final simdi = DateTime.now();
    String t(int gun) => programZamanYaz(simdi.subtract(Duration(days: gun)));
    await depo.sunucudanYaz([
      {..._sunucu(1, 'Ahmet', 1, tarih: t(2)), 'ekleyen': 1},
      {..._sunucu(2, 'Ahmet', 1, tarih: t(40)), 'ekleyen': 2},
      {..._sunucu(3, 'Ayşe', 1, tarih: t(200)), 'ekleyen': 1},
    ], []);
    expect(
      (await depo.liste(const YazismaFiltre())).map((e) => e.no).toList(),
      [1, 2, 3],
    );
    expect(
      (await depo.liste(const YazismaFiltre(donem: YazismaDonem.ay))).length,
      1,
    );
    expect(
      (await depo.liste(const YazismaFiltre(donem: YazismaDonem.ucAy))).length,
      2,
    );
    expect(
      (await depo.liste(const YazismaFiltre(donem: YazismaDonem.yil))).length,
      3,
    );
    expect((await depo.liste(const YazismaFiltre(kaydeden: 2))).single.no, 2);
    expect((await depo.liste(const YazismaFiltre(kisi: 'Ayşe'))).single.no, 3);
    expect(
      (await depo.liste(const YazismaFiltre(kelime: 'sunucu metni'))).length,
      3,
    );
    expect(await depo.sayi(), 3);
    final en = await depo.enCokYazilanlar();
    expect(en.first.kisi, 'Ahmet');
    expect(en.first.adet, 2);
  });

  test('sunucudan gelen, gönderilmemiş yerel değişikliği ezmez; silme ve uzlaştırma', () async {
    await depo.sunucudanYaz([_sunucu(9, 'Sunucu', 1)], []);
    final id = (await depo.noIle(9))!.yerelId!;
    await depo.kaydet({'kisi': 'Yerel'}, yerelId: id);
    await depo.sunucudanYaz([_sunucu(9, 'Sunucu 2', 2)], []);
    expect((await depo.getir(id))!.kisi, 'Yerel');

    await depo.sil(id);
    expect((await depo.kuyruk()).map((e) => e.tur).toList(), ['sil']);
    expect(await depo.sayi(), 0);

    await depo.sunucudanYaz([_sunucu(11, 'A', 1), _sunucu(12, 'B', 1)], []);
    expect(await depo.uzlastir({11}), 1);
    expect((await depo.noIle(12)), isNull);
  });

  test('çakışma: sunucudakini al ve benimkini gönder', () async {
    await depo.sunucudanYaz([_sunucu(20, 'Eski', 3)], []);
    final id = (await depo.noIle(20))!.yerelId!;
    await depo.kaydet({'kisi': 'Benim'}, yerelId: id);
    final op = (await depo.kuyruk()).single;
    await depo.islemSorunlu(
      op,
      'cakisma',
      'x',
      sunucu: _sunucu(20, 'Başkası', 5),
    );
    expect((await depo.sorunlular()).containsKey(id), true);
    final op2 = (await depo.sorunlular())[id]!;
    await depo.cakismaBenimkiniGonder(op2);
    final op3 = (await depo.kuyruk()).single;
    expect(op3.durum, 'bekliyor');
    expect(op3.taban, 5);
    await depo.islemSorunlu(
      op3,
      'cakisma',
      'x',
      sunucu: _sunucu(20, 'Başkası', 6),
    );
    await depo.cakismaSunucuyuAl((await depo.sorunlular())[id]!);
    expect((await depo.getir(id))!.kisi, 'Başkası');
    expect(await depo.kuyrukSayisi(), 0);
  });
}
