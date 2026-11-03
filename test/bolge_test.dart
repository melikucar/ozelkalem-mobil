import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/bakanlik.dart';
import 'package:ozelkalem/veri/bolge.dart';
import 'package:ozelkalem/veri/bolge_deposu.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _sunucu(
  int no,
  String mahalle,
  int surum, {
  int ilce = 1,
  String ilceAdi = 'Çukurova',
  String muhtar = '',
  String nufus = '',
}) => {
  'no': no,
  'surum': surum,
  'il': 1,
  'ilce': ilce,
  'semt': 0,
  'mahalle': 0,
  'ilce_adi': ilceAdi,
  'semt_adi': '',
  'mahalle_adi': mahalle,
  'tarih': '2026-10-01 10:00:00',
  'ekleyen': 1,
  'muhtar_adi': muhtar,
  'toplam_nufus': nufus,
};

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late BolgeDeposu depo;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = BolgeDeposu(yerel);
  });
  tearDown(() => yerel.kapat());

  test('doluluk: dolu bilgi alanlarının yüzdesi', () {
    final b = Bolge(Bolge.apiden(_sunucu(1, 'X', 1, muhtar: 'Ali')));
    expect(b.doluluk, closeTo(100 / bolgeBilgiAnahtarlari.length, 0.1));
    expect(b.baslik, 'X');
    expect(b.konum, 'Çukurova');
  });

  test('yeni bölge kuyruğa yazılır; listede ve aramada görünür', () async {
    final id = await depo.kaydet(
      {
        'ilce': 1,
        'semt': 0,
        'mahalle': 5,
        'muhtar_adi': 'Veli Yılmaz',
        'toplam_nufus': '1.250',
      },
      adlar: {'ilce': 'Çukurova', 'semt': '', 'mahalle': 'Yeni Köy'},
      il: 1,
    );
    final b = (await depo.getir(id))!;
    expect(b.bekleyen, true);
    expect(b.muhtar, 'Veli Yılmaz');
    final op = (await depo.kuyruk()).single;
    expect(op.no, isNull);
    expect(op.govde['muhtar_adi'], 'Veli Yılmaz');
    expect(op.govde['mahalle'], 5);
    expect((await depo.liste(const BolgeFiltre(kelime: 'yeni koy'))).length, 1);
    expect((await depo.liste(const BolgeFiltre(kelime: 'veli'))).length, 1);
    expect((await depo.ozet(const BolgeFiltre())).nufus, 1250);
  });

  test('düzenleme: bekleyen işleme birleşir; alanlar korunur', () async {
    await depo.sunucudanYaz([
      _sunucu(7, 'Köy A', 4, muhtar: 'Ali', nufus: '100'),
    ], []);
    final id = (await depo.getir(1)) == null ? 1 : 1;
    final yerelId = (await depo.liste(const BolgeFiltre())).first.yerelId!;
    expect(id, 1);
    await depo.kaydet(
      {'ilce': 1, 'muhtar_adi': 'Veli'},
      adlar: {'ilce': 'Çukurova', 'mahalle': 'Köy A'},
      yerelId: yerelId,
    );
    var op = (await depo.kuyruk()).single;
    expect(op.no, 7);
    expect(op.taban, 4);
    await depo.kaydet(
      {'ilce': 1, 'toplam_nufus': '200'},
      adlar: {'ilce': 'Çukurova', 'mahalle': 'Köy A'},
      yerelId: yerelId,
    );
    op = (await depo.kuyruk()).single; // aynı işlem, birleşti
    expect(op.govde['muhtar_adi'], 'Veli');
    expect(op.govde['toplam_nufus'], '200');
    final b = (await depo.getir(yerelId))!;
    expect(b.alan('muhtar_adi'), 'Veli');
    expect(b.alan('toplam_nufus'), '200');
  });

  test('sunucudan gelen yerel değişikliği ezmez; silme ve çakışma', () async {
    await depo.sunucudanYaz([_sunucu(9, 'Sunucu', 1)], []);
    final yerelId = (await depo.liste(const BolgeFiltre())).first.yerelId!;
    await depo.kaydet(
      {'ilce': 1, 'muhtar_adi': 'Yerel'},
      adlar: {'ilce': 'Çukurova', 'mahalle': 'Sunucu'},
      yerelId: yerelId,
    );
    await depo.sunucudanYaz([_sunucu(9, 'Sunucu', 2, muhtar: 'Başkası')], []);
    expect((await depo.getir(yerelId))!.muhtar, 'Yerel');

    final op = (await depo.kuyruk()).single;
    await depo.islemSorunlu(
      op,
      'cakisma',
      'x',
      sunucu: _sunucu(9, 'Sunucu', 5, muhtar: 'Başkası'),
    );
    await depo.cakismaSunucuyuAl((await depo.sorunlular())[yerelId]!);
    expect((await depo.getir(yerelId))!.muhtar, 'Başkası');
    expect(await depo.kuyrukSayisi(), 0);

    await depo.sil(yerelId);
    expect((await depo.kuyruk()).map((e) => e.tur).toList(), ['sil']);
    expect(await depo.sayi(), 0);

    await depo.sunucudanYaz([_sunucu(11, 'A', 1), _sunucu(12, 'B', 1)], []);
    expect(await depo.uzlastir({11}), 1);
  });

  test('ilçe süzgeci ve ilçe listesi', () async {
    await depo.sunucudanYaz([
      _sunucu(1, 'A', 1),
      _sunucu(2, 'B', 1, ilce: 2, ilceAdi: 'Girne'),
      _sunucu(3, 'C', 1, ilce: 2, ilceAdi: 'Girne'),
    ], []);
    final il = await depo.ilceler();
    expect(il.map((e) => (e.ad, e.adet)).toList(), [
      ('Çukurova', 1),
      ('Girne', 2),
    ]);
    expect((await depo.liste(const BolgeFiltre(ilce: 2))).length, 2);
  });

  test('bakanlık kurum grupları web ile aynı hiyerarşiyi verir', () {
    String g(String adi, String unvan) =>
        Kurum({'no': 1, 'katno': 1, 'adi': adi, 'unvan': unvan}).grup;
    expect(g('Ali', 'Adalet Bakanı'), '0|Bakan');
    expect(g('Veli', 'Bakan Yardımcısı'), '1|Bakan Yardımcıları');
    expect(g('X', 'Emniyet Genel Müdürü'), '2|Genel Müdürlükler');
    expect(g('X', 'Personel Dairesi Başkanlığı'), '4|Başkanlıklar');
    expect(g('X', 'İl Müdürlüğü'), '5|Müdürlükler');
    expect(
      g('X', 'Kuvvet Komutanı'),
      '7|Komutanlık, Rektörlük ve Diğer Birimler',
    );
    expect(g('Rastgele', ''), '8|Diğer');
  });
}
