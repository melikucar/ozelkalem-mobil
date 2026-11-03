import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/veri/genel_arama.dart';
import 'package:ozelkalem/veri/yazi_formatlari.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late YerelDb yerel;
  late GenelArama arama;

  setUp(() async {
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    arama = GenelArama(yerel);
    final db = yerel.db;
    Future<void> ekle(String tablo, Map<String, Object?> m, String ara) =>
        db.insert(tablo, {...m, 'ara': aramaMetni(ara)});
    await ekle('talepler', {
      'talep_eden': 'Çelik Ali',
      'tarih': '2026-10-30',
      'icerik': 'Yol talebi',
      'yapilan_islem': '',
    }, 'Çelik Ali 0532');
    await ekle('talepler', {
      'talep_eden': 'Veli',
      'tarih': '2026-09-01',
      'icerik': 'Çelik kapı bedeli',
      'yapilan_islem': '',
    }, 'Veli');
    await ekle('talepler', {
      'talep_eden': 'Silinen Çelik',
      'tarih': '2026-08-01',
      'silindi': 1,
    }, 'Silinen Çelik');
    await ekle('kisiler', {'adi': 'Ayşe Çelik', 'sira': 'ayse'}, 'Ayşe Çelik');
    await ekle('programlar', {
      'adi': 'Çelik fabrikası ziyareti',
      'tarih1': '2026-11-05 10:00:00',
    }, 'Çelik fabrikası ziyareti');
    await ekle('randevular', {
      'adi': 'Mehmet Çelik',
      'tarih': '2026-11-06 09:00:00',
    }, 'Mehmet Çelik');
    await ekle('gorusmeler', {
      'adi': 'Çelik Hanım',
      't1': '2026-10-01 12:00:00',
    }, 'Çelik Hanım');
    await ekle('faaliyetler', {
      'adi': 'Çelik Fuarı',
      'tarih': '2026-10-10 10:00:00',
    }, 'Çelik Fuarı');
    await ekle('yazismalar', {
      'kisi': 'Çelik Bakanı',
      'tarih': '2026-10-02 10:00:00',
    }, 'Çelik Bakanı');
    for (var i = 0; i < 14; i++) {
      await ekle('faaliyetler', {
        'adi': 'Çelik toplantı $i',
        'tarih': '2026-0${1 + i % 8}-0${1 + i % 8} 10:00:00',
      }, 'Çelik toplantı $i');
    }
  });
  tearDown(() => yerel.kapat());

  test('tüm yetkili modüllerde arar; silinenleri saymaz', () async {
    final s = await arama.ara('Çelik', (m) => true);
    final grup = {for (final g in s) g.anahtar: g};
    expect(s.map((g) => g.anahtar).toList(), [
      'talepler',
      'rehber',
      'programlar',
      'randevular',
      'gorusmeler',
      'faaliyetler',
      'yazismalar',
    ]);
    expect(grup['talepler']!.ogeler.map((o) => o.ad).toList(), [
      'Çelik Ali',
      'Veli',
    ]); // içerikte geçen de gelir, en yeni üstte
    expect(grup['rehber']!.ogeler.single.tarih, isNull);
    expect(grup['faaliyetler']!.ogeler.length, GenelArama.sinir);
  });

  test('ASCII yazım Türkçe harfli adları bulur', () async {
    final s = await arama.ara('celik', (m) => m == 'telefonlar');
    expect(s.map((g) => g.anahtar).toList(), ['rehber', 'gorusmeler']);
    expect(s.first.ogeler.single.ad, 'Ayşe Çelik');
  });

  test(
    'yetkisiz modüller aranmaz; boş ya da eşleşmeyen kelime boş döner',
    () async {
      final s = await arama.ara('çelik', (m) => m == 'talepler');
      expect(s.single.anahtar, 'talepler');
      expect(await arama.ara('  ', (m) => true), isEmpty);
      expect(await arama.ara('yokboyle', (m) => true), isEmpty);
      expect(GenelArama.aranabilir((m) => m == 'tbmm'), false);
      expect(GenelArama.aranabilir((m) => m == 'ajanda'), true);
    },
  );
}
