import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ozelkalem/moduller/raporlar/rapor_ortak.dart';

void main() {
  test('sayı biçimi (Türkçe)', () {
    expect(sayi(1234567), '1.234.567');
    expect(sayi(12.5, 1), '12,5');
    expect(sayi(12.0, 2), '12');
    expect(sayi(0), '0');
    expect(sayi('42'), '42');
    expect(sayi(null), '0');
    expect(sayi(-1500), '-1.500');
  });

  test('süzgeç sorgusu ve kopya', () {
    const f = RaporFiltre();
    expect(f.varsayilan, true);
    expect(f.sorgu['donem'], 'son365');
    final o = f.kopya(
      donem: 'ozel',
      bas: DateTime(2026, 1, 5),
      bit: DateTime(2026, 3, 31),
      kat: 3,
    );
    expect(o.sorgu['bas'], '2026-01-05');
    expect(o.sorgu['bit'], '2026-03-31');
    expect(o.sorgu['kat'], '3');
    expect(o.etkin, 1);
    final d = o.kopya(donem: 'bu_ay');
    expect(d.bas, isNull);
    expect(d.sorgu.containsKey('bas'), false);
    expect(d.kat, 3);
    expect(f.kopya(il: 6).varsayilan, false);
  });

  test('PHP boş dizisi nesne yerine geçer; tarih biçimi', () {
    expect(nesne([]), <String, dynamic>{});
    expect(nesne({'a': 1}), {'a': 1});
    expect(tarihTr('2026-10-30 12:00:00'), '30.10.2026');
    expect(tarihTr('2026-10-30', kisa: true), '30 Eki');
    expect(tarihTr(null), '');
    expect(
      liste([
        {'a': 1},
      ]).first['a'],
      1,
    );
    expect(donemAdi('son365'), 'Son 12 ay');
    expect(donemAdi('tumu'), 'Tüm zamanlar');
  });

  testWidgets('bileşenler makul boyutta çizilir; boş veri çökmez', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    final w = <Widget>[
      BarListe(ogeler: [BarOge('A', 40), BarOge('B', 10)], toplam: 50),
      const BarListe(ogeler: []),
      HalkaGrafik(
        ogeler: [BarOge('Olumlu', 40, no: 1), BarOge('Beklemede', 10, no: 2)],
        birim: 'talep',
      ),
      const HalkaGrafik(ogeler: [], birim: 'talep'),
      const SutunGrafik(
        etiketler: raporGunler,
        degerler: [1, 2, 3, 4, 5, 6, 7],
      ),
      const SutunGrafik(
        etiketler: raporGunler,
        degerler: [0, 0, 0, 0, 0, 0, 0],
      ),
      const IsiHaritasi(
        isi: {
          '2026': {'1': 5, '2': 8},
        },
      ),
      const IsiHaritasi(isi: {}),
      const TrendGrafik(
        seri: {
          'tur': 'ay',
          'etiket': ['2026-01-01', '2026-02-01'],
          'veri': [3, 5],
          'onceki': [1, 2],
        },
        cubuk: false,
        karsilastir: true,
      ),
      const TrendGrafik(
        seri: {
          'tur': 'gun',
          'etiket': ['2026-01-01'],
          'veri': [0],
          'onceki': [],
        },
        cubuk: true,
        karsilastir: false,
      ),
      const DeltaRozet(simdi: 5, once: 0),
      const DeltaRozet(simdi: 5, once: 4),
    ];
    for (final e in w) {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [e]),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byWidget(e)).height, lessThan(400));
    }
  });
}
