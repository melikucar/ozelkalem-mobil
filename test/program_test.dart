import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ozelkalem/api/api_istemci.dart';
import 'package:ozelkalem/api/token_deposu.dart';
import 'package:ozelkalem/senkron/senkron_motoru.dart';
import 'package:ozelkalem/veri/program.dart';
import 'package:ozelkalem/veri/program_deposu.dart';
import 'package:ozelkalem/veri/talep_deposu.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// PHP API'sinin ProgramlarController davranışını taklit eden bellek içi sunucu (talepler uçları boş döner).
class SahteProgramSunucusu {
  final Map<int, Map<String, dynamic>> kayitlar = {};
  final List<(int, int)> gunluk = [];
  final Map<String, Map<String, dynamic>> islemler = {};
  final List<Map<String, dynamic>> gelenKaydetler = [];
  int seq = 0;
  int sonNo = 500;
  bool programUclariYok = false;
  bool agKapali = false;

  int surum(int no) =>
      gunluk.where((g) => g.$2 == no).fold(0, (a, g) => g.$1 > a ? g.$1 : a);

  Map<String, dynamic> cikti(int no) => {...kayitlar[no]!, 'surum': surum(no)};

  void ekle(String adi, String t1, {String? t2}) {
    final no = ++sonNo;
    kayitlar[no] = {
      'no': no,
      'adi': adi,
      'tarih1': t1,
      'tarih2': t2 ?? t1,
      'yer': '',
      'notlar': '',
      'renk': '#3788d8',
      'randevu_no': 0,
      'ekleyen': 1,
      'hatirlaticilar': {'dakikalar': <int>[], 'kanal': null},
    };
    gunluk.add((++seq, no));
  }

  void degistir(int no, Map<String, dynamic> y) {
    kayitlar[no] = {...kayitlar[no]!, ...y};
    gunluk.add((++seq, no));
  }

  http.Response _ok(Object? v) => http.Response(
    jsonEncode({'ok': true, 'veri': v}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _hata(int d, String kod, String mesaj, [Map? ek]) =>
      http.Response(
        jsonEncode({
          'ok': false,
          'hata': {'kod': kod, 'mesaj': mesaj, ...?ek},
        }),
        d,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<http.Response> isle(http.Request r) async {
    if (agKapali) throw http.ClientException('ağ yok');
    final yol = r.url.path.replaceFirst('/api/v1/', '');
    if (yol.startsWith('programlar/') && programUclariYok) {
      return _hata(404, 'uc_yok', 'Uç bulunamadı.');
    }
    if (yol == 'talepler/referans') {
      return _ok({'durumlar': [], 'kategoriler': [], 'kaydedenler': []});
    }
    if (yol == 'talepler/degisenler') {
      return _ok({
        'degisen': [],
        'silinen': [],
        'imlec': 'e30',
        'devam': false,
      });
    }
    if (yol == 'talepler/idler') return _ok({'idler': []});
    if (yol == 'programlar/referans') {
      return _ok({'hazir': [], 'sms_kisiler': [], 'eposta_kisiler': []});
    }
    if (yol == 'programlar/idler') {
      return _ok({'idler': kayitlar.keys.toList()});
    }
    if (yol == 'programlar/degisenler') {
      final q = r.url.queryParameters;
      final limit = int.parse(q['limit'] ?? '300');
      String yaz(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      Map<String, dynamic> imlec;
      if (q['imlec'] == null) {
        imlec = {'i': 1 << 30, 'q': seq};
      } else {
        imlec = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(q['imlec']!))),
        ) as Map<String, dynamic>;
      }
      if (imlec.containsKey('i')) {
        final i = imlec['i'] as int;
        final l = kayitlar.keys.where((n) => n < i).toList()
          ..sort((a, b) => b.compareTo(a));
        final s = l.take(limit).toList();
        if (s.isNotEmpty) imlec['i'] = s.last;
        if (s.length < limit) imlec.remove('i');
        return _ok({
          'degisen': s.map(cikti).toList(),
          'silinen': <int>[],
          'imlec': yaz(imlec),
          'devam': s.length == limit,
        });
      }
      final qs = imlec['q'] as int;
      final yeni = gunluk.where((g) => g.$1 > qs).toList();
      final idler = yeni.map((g) => g.$2).toSet();
      imlec['q'] = yeni.isEmpty ? qs : yeni.last.$1;
      return _ok({
        'degisen': idler.where(kayitlar.containsKey).map(cikti).toList(),
        'silinen': idler.where((n) => !kayitlar.containsKey(n)).toList(),
        'imlec': yaz(imlec),
        'devam': false,
      });
    }
    final govde = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    if (yol == 'programlar/kaydet') {
      final id = govde['istemci_id'] as String;
      if (islemler.containsKey(id)) {
        return _ok({...islemler[id]!, 'tekrar': true});
      }
      gelenKaydetler.add(govde);
      final a = Map<String, dynamic>.from(govde['alanlar'] as Map);
      final no = (govde['no'] as num?)?.toInt();
      Map<String, dynamic> sonuc;
      if (no != null) {
        if (!kayitlar.containsKey(no)) return _hata(404, 'bulunamadi', 'yok');
        if (govde['taban'] != null &&
            (govde['taban'] as num).toInt() != surum(no)) {
          return _hata(409, 'cakisma', 'Değişmiş', {'sunucu': cikti(no)});
        }
        degistir(no, {...a});
        sonuc = {'program': cikti(no)};
      } else {
        ekle(
          a['adi'] as String,
          a['tarih1'] as String,
          t2: a['tarih2'] as String,
        );
        degistir(sonNo, {...a});
        sonuc = {'program': cikti(sonNo)};
      }
      islemler[id] = sonuc;
      return _ok(sonuc);
    }
    if (yol == 'programlar/sil') {
      final no = (govde['no'] as num).toInt();
      if (!kayitlar.containsKey(no)) return _hata(404, 'bulunamadi', 'yok');
      kayitlar.remove(no);
      gunluk.add((++seq, no));
      return _ok({'silindi': no});
    }
    return _hata(404, 'uc_yok', 'yok');
  }
}

void main() {
  sqfliteFfiInit();
  late SahteProgramSunucusu sunucu;
  late YerelDb yerel;
  late ProgramDeposu depo;
  late SenkronMotoru motor;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    sunucu = SahteProgramSunucusu();
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = ProgramDeposu(yerel);
    final td = TokenDeposu();
    await td.belirtecYaz('a', 'r');
    final api = ApiIstemci(td, istemci: MockClient(sunucu.isle));
    motor = SenkronMotoru(api, TalepDeposu(yerel), programlar: depo);
  });

  tearDown(() async {
    motor.dispose();
    await yerel.kapat();
  });

  Map<String, Object?> alan(String ad, String t1, String t2) => {
    'adi': ad,
    'tarih1': t1,
    'tarih2': t2,
    'yer': 'Makam',
    'notlar': '',
    'renk': '#12a150',
  };

  test(
    'ilk yükleme programları indirir, ikinci tur yalnızca delta ister',
    () async {
      for (var i = 0; i < 5; i++) {
        sunucu.ekle(
          'p$i',
          '2026-11-0${i + 1} 10:00:00',
          t2: '2026-11-0${i + 1} 11:00:00',
        );
      }
      await motor.senkronla();
      expect(motor.sonHata, isNull);
      expect(await depo.sayi(), 5);
      final liste = await depo.aralik(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 4),
      );
      expect(liste.map((p) => p.adi), [
        'p0',
        'p1',
        'p2',
      ]); // aralık + başlangıca göre sıralı
      sunucu.degistir(sunucu.sonNo, {'adi': 'yeni ad'});
      await motor.senkronla();
      expect((await depo.ara('yeni ad')).length, 1);
    },
  );

  test('çevrimdışı eklenen program kuyruğa girer, bağlantı gelince gider ve hatırlatıcı taşınır', () async {
    sunucu.agKapali = true;
    final id = await depo.kaydet(
      alan('Toplantı', '2026-11-10 14:00:00', '2026-11-10 15:00:00'),
      hatirlatici: const HatirlaticiAyar(
        dakikalar: [10, 60],
        sms: true,
        smsAlici: 'ben',
      ),
    );
    await motor.senkronla();
    expect(await depo.kuyrukSayisi(), 1);
    expect((await depo.getir(id))!.bekleyen, isTrue);

    sunucu.agKapali = false;
    await motor.senkronla();
    expect(await depo.kuyrukSayisi(), 0);
    final p = (await depo.getir(id))!;
    expect(p.bekleyen, isFalse);
    expect(p.no, isNotNull);
    final gonderilen = sunucu.gelenKaydetler.single;
    expect((gonderilen['hatirlaticilar'] as Map)['dakikalar'], [10, 60]);
    expect(((gonderilen['hatirlaticilar'] as Map)['kanal'] as Map)['sms'], 1);
    expect((gonderilen['alanlar'] as Map).containsKey('_hat'), isFalse);
  });

  test(
    'zamanı taşımak hatırlatıcıyı göndermez (sunucu başlangıca göre kaydırır)',
    () async {
      sunucu.ekle('x', '2026-11-12 09:00:00', t2: '2026-11-12 10:00:00');
      await motor.senkronla();
      final p = (await depo.aralik(
        DateTime(2026, 11, 12),
        DateTime(2026, 11, 13),
      )).single;
      await depo.tasi(
        p.yerelId!,
        DateTime(2026, 11, 12, 11),
        DateTime(2026, 11, 12, 12, 30),
      );
      await motor.senkronla();
      final g = sunucu.gelenKaydetler.single;
      expect(g.containsKey('hatirlaticilar'), isFalse);
      expect((g['alanlar'] as Map)['tarih1'], '2026-11-12 11:00:00');
      expect(sunucu.kayitlar[p.no]!['tarih2'], '2026-11-12 12:30:00');
    },
  );

  test(
    'çakışma sorunlu işaretlenir; sunucudakini almak yerel kaydı günceller',
    () async {
      sunucu.ekle('orijinal', '2026-11-15 09:00:00', t2: '2026-11-15 10:00:00');
      await motor.senkronla();
      final p = (await depo.aralik(
        DateTime(2026, 11, 15),
        DateTime(2026, 11, 16),
      )).single;
      sunucu.agKapali = true;
      await depo.kaydet(
        alan('benim', '2026-11-15 09:00:00', '2026-11-15 10:00:00'),
        yerelId: p.yerelId,
      );
      sunucu.degistir(p.no!, {'adi': 'başkasının'}); // sunucuda değişti
      sunucu.agKapali = false;
      await motor.senkronla();
      final sorunlu = await depo.sorunlular();
      expect(sorunlu[p.yerelId]!.durum, 'cakisma');
      expect((await depo.getir(p.yerelId!))!.adi, 'benim');
      await depo.cakismaSunucuyuAl(sorunlu[p.yerelId]!);
      expect((await depo.getir(p.yerelId!))!.adi, 'başkasının');
      expect(await depo.kuyrukSayisi(), 0);
    },
  );

  test('silme kuyruğa yazılır ve sunucudan da kaldırır; hiç gitmemiş program yalnızca yerelden kalkar', () async {
    sunucu.ekle('silinecek', '2026-11-20 09:00:00');
    await motor.senkronla();
    final p = (await depo.aralik(
      DateTime(2026, 11, 20),
      DateTime(2026, 11, 21),
    )).single;
    await depo.sil(p.yerelId!);
    expect(
      await depo.aralik(DateTime(2026, 11, 20), DateTime(2026, 11, 21)),
      isEmpty,
    );
    await motor.senkronla();
    expect(sunucu.kayitlar.containsKey(p.no), isFalse);
    expect(await depo.kuyrukSayisi(), 0);

    sunucu.agKapali = true;
    final y = await depo.kaydet(
      alan('geçici', '2026-11-21 09:00:00', '2026-11-21 10:00:00'),
    );
    await depo.sil(y);
    expect(await depo.kuyrukSayisi(), 0);
    expect(await depo.getir(y), isNull);
  });

  test('sunucuda program uçları yoksa talep senkronu bozulmaz', () async {
    sunucu.programUclariYok = true;
    await motor.senkronla();
    expect(motor.sonHata, isNull);
    expect(motor.programSenkron!.kullanilabilir, isFalse);
  });

  test('Türkçe karakterli arama ve gün kesişimi', () async {
    sunucu.ekle(
      'Çalışma Ziyareti',
      '2026-11-25 23:00:00',
      t2: '2026-11-26 02:00:00',
    );
    await motor.senkronla();
    expect((await depo.ara('calisma')).length, 1);
    expect(
      (await depo.aralik(
        DateTime(2026, 11, 26),
        DateTime(2026, 11, 27),
      )).length,
      1,
    ); // gece yarısını aşan program ertesi güne de değer
  });

  test('hatırlatıcı ayarı JSON gidiş-dönüşü ve etiketler', () {
    final a = HatirlaticiAyar.fromJson(
      const HatirlaticiAyar(
        dakikalar: [1440, 10],
        eposta: true,
        epostaAlici: 'secilen',
        epostaKisiler: [3, 4],
      ).toJson(),
    );
    expect(a.dakikalar, [10, 1440]);
    expect(a.eposta, isTrue);
    expect(a.epostaKisiler, [3, 4]);
    expect(hatirlaticiEtiketi(0), 'Zamanında');
    expect(hatirlaticiEtiketi(90), '90 dk önce');
    expect(hatirlaticiEtiketi(120), '2 saat önce');
    expect(hatirlaticiEtiketi(2880), '2 gün önce');
    expect(hatirlaticiEtiketi(10080), '1 hafta önce');
  });
}
