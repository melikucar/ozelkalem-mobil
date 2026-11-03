import 'dart:convert';

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ozelkalem/api/api_istemci.dart';
import 'package:ozelkalem/api/token_deposu.dart';
import 'package:ozelkalem/senkron/senkron_motoru.dart';
import 'package:ozelkalem/veri/talep_deposu.dart';
import 'package:ozelkalem/veri/talep_filtre.dart';
import 'package:ozelkalem/veri/yerel_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// PHP API'sinin (TaleplerController) davranışını taklit eden bellek içi sunucu.
class SahteSunucu {
  final Map<int, Map<String, dynamic>> kayitlar = {};
  final List<(int, int)> gunluk = []; // (seq, no)
  int seq = 0;
  int sonNo = 1000;
  final Map<String, Map<String, dynamic>> islemler = {};
  bool agKapali = false;
  bool yanitiKaybet = false; // işlem yapılır ama istemci yanıtı alamaz
  int gunlukTemizlik = 0;
  int istekSayisi = 0;
  int? kesIstek; // bu sıradaki istek ağ hatasıyla kesilir (yarım kalan yükleme testi)
  final List<String> yollar = [];
  Map<String, dynamic>? sonEkstra;
  final List<Map<String, String>> yuklemeler = []; // {no, istemci_id, govde}
  final List<String> silinenDosyalar = [];

  int surum(int no) =>
      gunluk.where((g) => g.$2 == no).fold(0, (a, g) => g.$1 > a ? g.$1 : a);

  Map<String, dynamic> _cikti(int no) => {...kayitlar[no]!, 'surum': surum(no)};

  /// Web'den/başka cihazdan yapılan değişiklik.
  void ekle(String ad, {int durum = 1, String tarih = '2026-10-01'}) {
    final no = ++sonNo;
    kayitlar[no] = _yeni(no, ad, durum, tarih);
    gunluk.add((++seq, no));
  }

  void degistir(int no, Map<String, dynamic> patch) {
    kayitlar[no] = {...kayitlar[no]!, ...patch};
    gunluk.add((++seq, no));
  }

  void sil(int no) {
    kayitlar.remove(no);
    gunluk.add((++seq, no));
  }

  Map<String, dynamic> _yeni(int no, String ad, int durum, String tarih) => {
    'no': no,
    'il': 0,
    'ilce': 0,
    'semt': 0,
    'mahalle': 0,
    'talep_eden': ad.toUpperCase(),
    'tcno': '',
    'icerik': '<p>x</p>',
    'telefon': '0532',
    'katno': 0,
    'mulakat_tarihi': null,
    'mulakat_yeri': '',
    'referans': '',
    'referans_telefon': '',
    'tarih': tarih,
    'durum': durum,
    'yapilan_islem': '',
    'sonuc': '',
    'ilgili_kurum': '',
    'hatirlatici': 0,
    'hatirlatici_tarih': null,
    'ekleyen': 1,
  };

  http.Response _ok(Object? veri) => http.Response(
    jsonEncode({'ok': true, 'veri': veri}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  http.Response _hata(
    int d,
    String kod,
    String m, [
    Map<String, dynamic> ek = const {},
  ]) => http.Response(
    jsonEncode({
      'ok': false,
      'hata': {'kod': kod, 'mesaj': m, ...ek},
    }),
    d,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> isle(http.Request r) async {
    istekSayisi++;
    if (agKapali || istekSayisi == kesIstek) {
      throw http.ClientException('ağ yok');
    }
    final yol = r.url.path.replaceFirst('/api/v1/', '');
    yollar.add('${r.method} $yol');
    if (r.headers['Authorization'] != 'Bearer a') {
      return _hata(401, 'oturum_gecersiz', 'x');
    }
    if (yol == 'talepler/dosya-yukle') {
      final no = RegExp(r'name="no"\r\n\r\n(\d+)').firstMatch(r.body)?.group(1);
      final id =
          RegExp(r'name="istemci_id"\r\n\r\n([^\r]+)')
              .firstMatch(r.body)
              ?.group(1) ??
          '';
      if (no == null || !kayitlar.containsKey(int.parse(no))) {
        return _hata(404, 'bulunamadi', 'Talep bulunamadı.');
      }
      if (!islemler.containsKey(id)) {
        yuklemeler.add({'no': no, 'istemci_id': id, 'govde': r.body});
        islemler[id] = {
          'dosya': {'ad': '$no-x', 'goruntu': 'x', 'boyut': 1},
        };
      }
      return _ok(islemler[id]);
    }
    final govde = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    final q = r.url.queryParameters;
    if (yol == 'talepler/dosya-sil') {
      silinenDosyalar.add('${govde['no']}:${govde['ad']}');
      return _ok({'silindi': govde['ad']});
    }
    if (yol == 'talepler/detay') {
      final no = int.parse(q['no']!);
      if (!kayitlar.containsKey(no)) {
        return _hata(404, 'bulunamadi', 'Talep bulunamadı.');
      }
      return _ok({
        'no': no,
        'ekleyen': 'Test Kullanıcı',
        'dosyalar': [],
        'smsler': [],
        'ust_yazilar': [],
        'gecmis': [],
        'rehber': {'var': false, 'kara_liste': false, 'kategori': 0},
      });
    }

    if (yol == 'talepler/referans') {
      return _ok({
        'kategoriler': [
          {'no': 1, 'adi': 'Sağlık'},
        ],
        'durumlar': [
          {'no': 1, 'adi': 'Beklemede', 'renk': '#ccc'},
          {'no': 2, 'adi': 'Olumlu', 'renk': '#0f0'},
        ],
      });
    }
    if (yol == 'talepler/idler') {
      return _ok({'idler': kayitlar.keys.toList()..sort()});
    }
    if (yol == 'talepler/degisenler') return _degisenler(q);
    if (yol == 'talepler/kaydet' || yol == 'talepler/sil') {
      final id = govde['istemci_id'] as String;
      if (islemler.containsKey(id)) {
        return _ok({...islemler[id]!, 'tekrar': true});
      }
      final sonuc = yol.endsWith('kaydet') ? _kaydet(govde) : _silIstegi(govde);
      if (sonuc is http.Response) return sonuc;
      islemler[id] = sonuc as Map<String, dynamic>;
      if (yanitiKaybet) {
        yanitiKaybet = false;
        throw http.ClientException('yanıt kayboldu');
      }
      return _ok(sonuc);
    }
    return _hata(404, 'uc_yok', 'yok');
  }

  Object _kaydet(Map<String, dynamic> g) {
    final a = Map<String, dynamic>.from(g['alanlar'] as Map);
    if ((a['talep_eden'] as String?)?.isEmpty ?? true) {
      return _hata(422, 'zorunlu_alan', 'Talep eden zorunlu.');
    }
    sonEkstra = g['ekstra'] == null
        ? null
        : Map<String, dynamic>.from(g['ekstra'] as Map);
    final no = (g['no'] as num?)?.toInt();
    if (no != null) {
      if (!kayitlar.containsKey(no)) {
        return _hata(404, 'bulunamadi', 'Talep bulunamadı.');
      }
      if (g['taban'] != null && (g['taban'] as num).toInt() != surum(no)) {
        return _hata(409, 'cakisma', 'Değiştirilmiş', {'sunucu': _cikti(no)});
      }
      degistir(no, {
        ...a,
        'talep_eden': (a['talep_eden'] as String).toUpperCase(),
      });
      return {'talep': _cikti(no)};
    }
    final yeniNo = ++sonNo;
    kayitlar[yeniNo] = {
      ..._yeni(
        yeniNo,
        a['talep_eden'] as String,
        (a['durum'] as num?)?.toInt() ?? 1,
        (a['tarih'] ?? '2026-10-29') as String,
      ),
    };
    gunluk.add((++seq, yeniNo));
    return {'talep': _cikti(yeniNo)};
  }

  Object _silIstegi(Map<String, dynamic> g) {
    final no = (g['no'] as num).toInt();
    if (!kayitlar.containsKey(no)) {
      return _hata(404, 'bulunamadi', 'Talep bulunamadı.');
    }
    sil(no);
    return {'silindi': no};
  }

  http.Response _degisenler(Map<String, String> q) {
    final hizli = int.tryParse(q['hizli'] ?? '');
    if (hizli != null) {
      // tarihe göre en yeni N kayıt; imleç dönmez, tam yükleme ayrıca sürer
      final nolar = kayitlar.keys.toList()..sort((a, b) => b.compareTo(a));
      return _ok({
        'degisen': [for (final n in nolar.take(hizli)) _cikti(n)],
        'silinen': <int>[],
        'imlec': null,
        'devam': false,
      });
    }
    final limit = int.parse(q['limit'] ?? '300');
    Map<String, dynamic> imlec;
    if (q['imlec'] == null) {
      imlec = {'i': 2147483647, 'q': seq};
      if (q['tarih_baslangic'] != null) imlec['tb'] = q['tarih_baslangic'];
    } else {
      imlec = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(q['imlec']!))),
      ) as Map<String, dynamic>;
      if ((imlec['q'] as int) < gunlukTemizlik) {
        return _hata(410, 'imlec_eski', 'eski');
      }
    }
    String yaz(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

    if (imlec.containsKey('i')) {
      final i = imlec['i'] as int;
      var liste = kayitlar.keys.where((n) => n < i).toList()
        ..sort((a, b) => b.compareTo(a));
      if (imlec['tb'] != null) {
        liste = liste
            .where(
              (n) =>
                  (kayitlar[n]!['tarih'] as String).compareTo(
                    imlec['tb'] as String,
                  ) >=
                  0,
            )
            .toList();
      }
      final sayfa = liste.take(limit).toList();
      final devam = sayfa.length == limit;
      if (sayfa.isNotEmpty) imlec['i'] = sayfa.last;
      if (!devam) imlec.remove('i');
      return _ok({
        'degisen': sayfa.map(_cikti).toList(),
        'silinen': [],
        'imlec': yaz(imlec),
        'devam': devam,
      });
    }
    final s = gunluk
        .where((g) => g.$1 > (imlec['q'] as int))
        .take(limit)
        .toList();
    final idler = s.map((g) => g.$2).toSet();
    if (s.isNotEmpty) imlec['q'] = s.last.$1;
    return _ok({
      'degisen': idler.where(kayitlar.containsKey).map(_cikti).toList(),
      'silinen': idler.where((n) => !kayitlar.containsKey(n)).toList(),
      'imlec': yaz(imlec),
      'devam': s.length == limit,
    });
  }
}

void main() {
  sqfliteFfiInit();
  late SahteSunucu sunucu;
  late YerelDb yerel;
  late TalepDeposu depo;
  late SenkronMotoru motor;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    sunucu = SahteSunucu();
    yerel = await YerelDb.ac(inMemoryDatabasePath, fabrika: databaseFactoryFfi);
    depo = TalepDeposu(yerel);
    final td = TokenDeposu();
    await td.belirtecYaz('a', 'r');
    final api = ApiIstemci(td, istemci: MockClient(sunucu.isle));
    motor = SenkronMotoru(api, depo);
  });

  tearDown(() async {
    motor.dispose();
    await yerel.kapat();
  });

  Map<String, Object?> alan(String ad, {int durum = 1}) => {
    'talep_eden': ad,
    'telefon': '0555',
    'durum': durum,
    'tarih': '2026-10-29',
  };

  test('ilk yükleme sayfa sayfa iner, ikinci tur boş', () async {
    for (var i = 0; i < 650; i++) {
      sunucu.ekle('kişi $i');
    }
    await motor.senkronla();
    expect(motor.sonHata, isNull);
    expect(await depo.sayi(), 650);
    expect((await depo.durumlar()).length, 2);
    final onceki = sunucu.istekSayisi;
    await motor.senkronla();
    expect(await depo.sayi(), 650);
    expect(
      sunucu.istekSayisi - onceki,
      1,
    ); // yalnızca delta: referans ve uzlaştırma önbellekte
  });

  test(
    'yarıda kesilen ilk yükleme baştan başlamaz, kaldığı yerden sürer',
    () async {
      for (var i = 0; i < 650; i++) {
        sunucu.ekle('kişi $i');
      }
      // ilk istekler: hızlı görünüm, referans (2), 1. ve 2. sayfa; 6. istek kesilir
      sunucu.kesIstek =
          sunucu.istekSayisi +
          6; // hızlı görünüm, referans (2 istek), 2 sayfa; 6. istek kesilir
      await motor.senkronla();
      expect(motor.sonHata, isNotNull);
      final yarim = await depo.sayi();
      expect(yarim, 600);

      final once = sunucu.yollar.length;
      await motor.senkronla();
      expect(motor.sonHata, isNull);
      expect(await depo.sayi(), 650);
      final sayfalar = sunucu.yollar
          .skip(once)
          .where((y) => y == 'GET talepler/degisenler')
          .length;
      expect(
        sayfalar,
        1,
      ); // yalnızca kalan 50 kayıt: 650 kaydın tamamı yeniden indirilmedi
    },
  );

  test('sunucudaki ekleme/güncelleme/silme yerele yansır', () async {
    sunucu.ekle('ali');
    sunucu.ekle('veli');
    await motor.senkronla();
    sunucu.degistir(1001, {'durum': 2});
    sunucu.sil(1002);
    sunucu.ekle('can');
    await motor.senkronla();
    final l = await depo.liste();
    expect(l.map((t) => t.no).toSet(), {1001, 1003});
    expect(l.firstWhere((t) => t.no == 1001).durum, 2);
  });

  test('çevrimdışı oluşturma ve düzenleme birleşir, bağlantı gelince tek istek gider', () async {
    sunucu.agKapali = true;
    final id = await depo.kaydet(alan('mehmet uzun'));
    await depo.kaydet(alan('mehmet uzun duzeltilmis'), yerelId: id);
    expect((await depo.kuyruk()).length, 1);
    expect((await depo.liste()).first.talepEden, 'mehmet uzun duzeltilmis');
    await motor.senkronla();
    expect(motor.cevrimdisi, isTrue);
    expect((await depo.kuyruk()).length, 1);

    sunucu.agKapali = false;
    await motor.senkronla();
    expect(await depo.kuyruk(), isEmpty);
    final t = (await depo.getir(id))!;
    expect(t.no, isNotNull);
    expect(t.bekleyen, isFalse);
    expect(t.talepEden, 'MEHMET UZUN DUZELTILMIS');
    expect(sunucu.kayitlar.length, 1);
  });

  test(
    'yanıt kaybolursa yeniden denemek kaydı çoğaltmaz (istemci_id)',
    () async {
      sunucu.yanitiKaybet = true;
      await depo.kaydet(alan('tek kayıt'));
      await motor.senkronla();
      expect(motor.cevrimdisi, isTrue);
      expect((await depo.kuyruk()).length, 1);
      await motor.senkronla();
      expect(await depo.kuyruk(), isEmpty);
      expect(sunucu.kayitlar.length, 1);
      expect(await depo.sayi(), 1);
    },
  );

  test(
    'gönderilmemiş yerel değişiklik sunucudan gelen veriyle ezilmez',
    () async {
      sunucu.ekle('ali');
      await motor.senkronla();
      final t = (await depo.liste()).first;
      sunucu.agKapali = true;
      await depo.kaydet({...t.alanlar(), 'telefon': '111'}, yerelId: t.yerelId);
      sunucu.agKapali = false;
      sunucu.degistir(1001, {'telefon': '999'});
      // gönderme çakışır; çekme yerel kaydı ezmemeli
      await motor.senkronla();
      final k = (await depo.getir(t.yerelId!))!;
      expect(k.telefon, '111');
      expect((await depo.kuyruk(durum: 'cakisma')).length, 1);
    },
  );

  test('çakışma: sunucu sürümünü al', () async {
    sunucu.ekle('ali');
    await motor.senkronla();
    final t = (await depo.liste()).first;
    await depo.kaydet({...t.alanlar(), 'telefon': '111'}, yerelId: t.yerelId);
    sunucu.degistir(1001, {'telefon': '999'});
    await motor.senkronla();
    final op = (await depo.kuyruk(durum: 'cakisma')).single;
    await depo.cakismaSunucuyuAl(op);
    final k = (await depo.getir(t.yerelId!))!;
    expect(k.telefon, '999');
    expect(k.bekleyen, isFalse);
    expect(await depo.kuyruk(), isEmpty);
  });

  test('çakışma: benim sürümümü gönder', () async {
    sunucu.ekle('ali');
    await motor.senkronla();
    final t = (await depo.liste()).first;
    await depo.kaydet({...t.alanlar(), 'telefon': '111'}, yerelId: t.yerelId);
    sunucu.degistir(1001, {'telefon': '999'});
    await motor.senkronla();
    await depo.cakismaBenimkiniGonder(
      (await depo.kuyruk(durum: 'cakisma')).single,
    );
    await motor.senkronla();
    expect(sunucu.kayitlar[1001]!['telefon'], '111');
    expect(await depo.kuyruk(), isEmpty);
    expect((await depo.getir(t.yerelId!))!.bekleyen, isFalse);
  });

  test('silme: eşitlenmiş kayıt kuyruğa girer, yalnızca yerel kayıt sunucuya hiç gitmez', () async {
    sunucu.ekle('ali');
    await motor.senkronla();
    final eslenmis = (await depo.liste()).first;
    final yerelKayit = await depo.kaydet(alan('sadece yerel'));
    await depo.sil(yerelKayit);
    await depo.sil(eslenmis.yerelId!);
    expect(await depo.liste(), isEmpty);
    expect((await depo.kuyruk()).map((o) => o.tur), ['sil']);
    await motor.senkronla();
    expect(sunucu.kayitlar, isEmpty);
    expect(await depo.kuyruk(), isEmpty);
    expect(sunucu.yollar.where((y) => y.contains('kaydet')), isEmpty);
  });

  test('doğrulama hatası kuyruğu tıkamaz, diğer kayıtlar gider', () async {
    await depo.kaydet(alan('')); // sunucu 422 verir
    await depo.kaydet(alan('geçerli'));
    await motor.senkronla();
    expect((await depo.kuyruk(durum: 'hata')).length, 1);
    expect(sunucu.kayitlar.length, 1);
    final hata = (await depo.kuyruk(durum: 'hata')).single;
    await depo.islemiIptalEt(hata);
    expect(await depo.kuyruk(durum: 'hata'), isEmpty);
    expect(await depo.sayi(), 1);
  });

  test(
    'günlük temizlenince (410) baştan yüklenir ve hayalet kayıtlar silinir',
    () async {
      sunucu.ekle('ali');
      sunucu.ekle('veli');
      await motor.senkronla();
      sunucu.kayitlar.remove(1002); // günlüğe yazılmadan kaybolan kayıt
      sunucu.gunlukTemizlik = sunucu.seq + 5;
      await motor.senkronla();
      expect(motor.sonHata, isNull);
      expect((await depo.liste()).map((t) => t.no), [1001]);
    },
  );

  test(
    'ekstra seçenekler (SMS, rehber, kara liste) kayıtla birlikte gönderilir',
    () async {
      await depo.kaydet(
        alan('ekstra deneme'),
        ekstra: {
          'sms_gonder': 1,
          'sms_talep_eden': 1,
          'rehber_kayit': 1,
          'rehber_kategori': 2,
          'kara_liste': 0,
        },
      );
      await motor.senkronla();
      expect(sunucu.sonEkstra, {
        'sms_gonder': 1,
        'sms_talep_eden': 1,
        'rehber_kayit': 1,
        'rehber_kategori': 2,
        'kara_liste': 0,
      });
      expect(await depo.kuyruk(), isEmpty);
    },
  );

  test('çevrimdışı oluşturulan talebe eklenen dosya, talep gittikten sonra yüklenir', () async {
    sunucu.agKapali = true;
    final id = await depo.kaydet(alan('dosyali kayit'));
    final gecici = File(
      '${Directory.systemTemp.path}/ozelkalem_test_${DateTime.now().microsecondsSinceEpoch}.txt',
    )..writeAsStringSync('icerik');
    await depo.dosyaEkle(id, yol: gecici.path, ad: 'not.txt', boyut: 6);
    expect((await depo.kuyruk()).map((o) => o.tur), ['kaydet', 'dosya']);

    sunucu.agKapali = false;
    await motor.senkronla();
    expect(await depo.kuyruk(), isEmpty);
    expect(sunucu.yuklemeler, hasLength(1));
    expect(
      sunucu.yuklemeler.single['no'],
      '${(await depo.getir(id))!.no}',
    ); // talebin sunucu numarasıyla
    expect(gecici.existsSync(), isFalse); // gönderilen yerel kopya temizlenir
    expect(
      await depo.ekOku((await depo.getir(id))!.no!),
      isNotNull,
    ); // ayrıntı önbelleği yenilendi
  });

  test('bekleyen dosya vazgeçilince yerel kopya silinir ve kuyruktan kalkar', () async {
    final id = await depo.kaydet(alan('vazgec'));
    final gecici = File(
      '${Directory.systemTemp.path}/ozelkalem_test_${DateTime.now().microsecondsSinceEpoch}.txt',
    )..writeAsStringSync('x');
    await depo.dosyaEkle(id, yol: gecici.path, ad: 'x.txt', boyut: 1);
    await depo.dosyaIsleminiIptalEt((await depo.dosyaIslemleri(id)).single);
    expect(gecici.existsSync(), isFalse);
    expect(await depo.dosyaIslemleri(id), isEmpty);
  });

  test('yerel talebi silmek bekleyen dosya işlemlerini de temizler', () async {
    final id = await depo.kaydet(alan('silinecek'));
    final gecici = File(
      '${Directory.systemTemp.path}/ozelkalem_test_${DateTime.now().microsecondsSinceEpoch}.txt',
    )..writeAsStringSync('x');
    await depo.dosyaEkle(id, yol: gecici.path, ad: 'x.txt', boyut: 1);
    await depo.sil(id);
    expect(await depo.kuyruk(), isEmpty);
    expect(gecici.existsSync(), isFalse);
  });

  test(
    'sunucudaki ek dosyanın silinmesi kuyruğa girer ve gönderilir',
    () async {
      sunucu.ekle('ali');
      await motor.senkronla();
      final t = (await depo.liste()).first;
      await depo.sunucuDosyasiniSil(t.yerelId!, t.no!, '${t.no}-belge.pdf');
      await motor.senkronla();
      expect(sunucu.silinenDosyalar, ['${t.no}:${t.no}-belge.pdf']);
      expect(await depo.kuyruk(), isEmpty);
    },
  );

  test(
    'veritabanı v1 → v2 yükseltmesi eski veriyi korur ve yeni tabloları ekler',
    () async {
      final ad = 'yukselt_${DateTime.now().microsecondsSinceEpoch}.db';
      final yol = '${await databaseFactoryFfi.getDatabasesPath()}/$ad';
      final eski = await databaseFactoryFfi.openDatabase(
        yol,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            await db.execute(
              'CREATE TABLE meta (anahtar TEXT PRIMARY KEY, deger TEXT)',
            );
            await db.insert('meta', {'anahtar': 'imlec', 'deger': 'abc'});
          },
        ),
      );
      await eski.close();
      final yeni = await YerelDb.ac(ad, fabrika: databaseFactoryFfi);
      final tablolar = (await yeni.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name']).toSet();
      expect(tablolar, containsAll(['talep_ek', 'adres_onbellek']));
      expect((await yeni.db.query('meta')).single['deger'], 'abc');
      await yeni.kapat();
      await databaseFactoryFfi.deleteDatabase(yol);
    },
  );

  test(
    'gelişmiş filtreler birlikte çalışır, çip sayıları seçili durumu saymaz',
    () async {
      sunucu.ekle('Ali Kaya', durum: 1, tarih: '2026-10-01'); // 1
      sunucu.ekle('Veli Demir', durum: 2, tarih: '2026-10-05'); // 2
      sunucu.ekle('Can Yılmaz', durum: 2, tarih: '2026-10-10'); // 3
      sunucu.ekle('Ece Arslan', durum: 3, tarih: '2026-09-20'); // 4
      sunucu.degistir(1001, {
        'katno': 7,
        'ilce': 50,
        'ekleyen': 9,
        'telefon': '0(532) 111 22 33',
      });
      sunucu.degistir(1002, {
        'katno': 7,
        'ilce': 51,
        'ekleyen': 9,
        'telefon': '0(533) 444 55 66',
        'hatirlatici': 1,
      });
      sunucu.degistir(1003, {
        'katno': 8,
        'ilce': 50,
        'ekleyen': 10,
        'telefon': '0(542) 777 88 99',
        'icerik': '<p>Yol çalışması</p>',
      });
      sunucu.degistir(1004, {
        'ilgili_kurum': 'Belediye',
        'telefon': '0(555) 000 11 22',
      });
      await motor.senkronla();

      Future<List<int?>> nolar(TalepFiltre f) async =>
          (await depo.liste(filtre: f)).map((t) => t.no).toList()..sort();

      expect(await nolar(const TalepFiltre(durumlar: {2})), [1002, 1003]);
      expect(await nolar(const TalepFiltre(durumlar: {1, 3})), [1001, 1004]);
      expect(await nolar(const TalepFiltre(kategoriler: {7})), [1001, 1002]);
      expect(await nolar(const TalepFiltre(ilce: 50)), [1001, 1003]);
      expect(await nolar(const TalepFiltre(kaydeden: 10)), [1003]);
      expect(await nolar(const TalepFiltre(telefon: '533 444')), [1002]);
      expect(await nolar(const TalepFiltre(telefon: '(0542)')), [1003]);
      expect(
        await nolar(const TalepFiltre(bas: '2026-10-01', bit: '2026-10-05')),
        [1001, 1002],
      );
      expect(await nolar(const TalepFiltre(hatirlatici: true)), [1002]);
      expect(await nolar(const TalepFiltre(arama: 'yol çalışması')), [
        1003,
      ]); // içerikte arar
      expect(await nolar(const TalepFiltre(arama: 'belediye')), [
        1004,
      ]); // kurumda arar
      expect(await nolar(const TalepFiltre(durumlar: {2}, ilce: 50)), [1003]);

      final sayilar = await depo.durumSayilari(
        const TalepFiltre(durumlar: {2}, kategoriler: {7}),
      );
      expect(sayilar, {
        1: 1,
        2: 1,
      }); // durum seçimi yok sayılır, kategori uygulanır
      expect(await depo.sonucSayisi(const TalepFiltre(durumlar: {2})), 2);
    },
  );

  test('sıralama seçenekleri ve ilçe/kaydeden seçenekleri', () async {
    sunucu.ekle('Zeynep', tarih: '2026-10-02');
    sunucu.ekle('Ahmet', tarih: '2026-10-09');
    sunucu.degistir(1001, {'il': 6, 'ilce': 60});
    sunucu.degistir(1002, {'il': 6, 'ilce': 60});
    await motor.senkronla();
    await depo.adresYaz('ilce:6', [
      {'id': 60, 'ad': 'Çankaya'},
    ]);

    Future<List<String>> adlar(TalepSirala s) async =>
        (await depo.liste(filtre: TalepFiltre(sirala: s)))
            .map((t) => t.talepEden)
            .toList();
    expect(await adlar(TalepSirala.yeni), ['AHMET', 'ZEYNEP']);
    expect(await adlar(TalepSirala.eski), ['ZEYNEP', 'AHMET']);
    expect(await adlar(TalepSirala.ad), ['AHMET', 'ZEYNEP']);
    expect(await adlar(TalepSirala.kayit), ['AHMET', 'ZEYNEP']);

    final ilceler = await depo.ilceSecenekleri();
    expect(ilceler.single, (id: 60, ad: 'Çankaya', adet: 2));
  });

  test('filtre özeti: panel sayısı ve temizleme', () {
    const f = TalepFiltre(
      arama: 'a',
      durumlar: {1},
      kategoriler: {2},
      ilce: 3,
      bas: '2026-01-01',
      bekleyen: true,
    );
    expect(f.panelSayisi, 4);
    expect(f.daraltiyor, isTrue);
    final t = f.panelTemiz();
    expect(t.panelSayisi, 0);
    expect(t.arama, 'a');
    expect(t.durumlar, {1});
    expect(const TalepFiltre().daraltiyor, isFalse);
    expect(f.kopya(ilce: null).ilce, isNull);
    expect(f.kopya(arama: 'b').ilce, 3);
  });

  test('arama Türkçe karakterleri katlar', () async {
    sunucu.ekle('Işıl Çelik');
    sunucu.ekle('Mehmet');
    await motor.senkronla();
    expect((await depo.liste(arama: 'isil celik')).length, 1);
    expect((await depo.liste(arama: 'ÇELİK')).length, 1);
    expect((await depo.liste(arama: 'zzz')).length, 0);
  });
}
