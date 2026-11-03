import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'yazi_formatlari.dart';
import 'talep.dart';
import 'talep_filtre.dart';
import 'yerel_db.dart';

/// Giden kuyruktaki bir işlem (sunucuya henüz ulaşmamış yerel değişiklik).
class KuyrukOp {
  KuyrukOp(this.satir);

  final Map<String, Object?> satir;

  int get id => satir['id'] as int;
  String get istemciId => satir['istemci_id'] as String;
  String get tur => satir['tur'] as String; // kaydet | sil
  int get yerelId => satir['yerel_id'] as int;
  int? get no => satir['no'] as int?;
  int? get taban => satir['taban'] as int?;
  String get durum => satir['durum'] as String; // bekliyor | cakisma | hata
  String get mesaj => (satir['mesaj'] ?? '') as String;
  Map<String, dynamic> get govde =>
      jsonDecode((satir['govde'] ?? '{}') as String) as Map<String, dynamic>;
  Map<String, dynamic>? get sunucu {
    final s = satir['sunucu_json'] as String?;
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }
}

/// Talepler için yerel veri erişimi + giden kuyruk. Ekranlar ve senkron motoru yalnızca bunu kullanır.
class TalepDeposu extends ChangeNotifier {
  TalepDeposu(this._yerel);

  final YerelDb _yerel;
  Database get _db => _yerel.db;

  static const _uuid = Uuid();

  static const _metinZorunlu = [
    'talep_eden',
    'tcno',
    'icerik',
    'telefon',
    'mulakat_yeri',
    'referans',
    'referans_telefon',
    'yapilan_islem',
    'sonuc',
    'ilgili_kurum',
  ];
  static const _sayiZorunlu = ['katno', 'durum', 'hatirlatici'];

  /// Satırı yerel şemaya uygun hale getirir (null → boş/0) ve arama metnini üretir.
  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in _metinZorunlu) {
      if (r.containsKey(k)) r[k] = (r[k] ?? '').toString();
    }
    for (final k in _sayiZorunlu) {
      if (r.containsKey(k)) r[k] = (r[k] as num?)?.toInt() ?? 0;
    }
    return r;
  }

  static String _ara(Map<String, Object?> m) => aramaMetni(
    '${m['talep_eden'] ?? ''} ${m['telefon'] ?? ''} ${m['referans'] ?? ''} ${m['tcno'] ?? ''}',
  );

  void _bildir() => notifyListeners();

  // Toplu yüklemede (sunucudan sayfa sayfa gelen kayıtlar) ekranlar saniyede en çok bir kez tazelenir; arayüz akıcı kalır.
  DateTime _sonBildirim = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _bildirimZamani;

  void _seyrekBildir() {
    const aralik = Duration(milliseconds: 1500);
    final gecen = DateTime.now().difference(_sonBildirim);
    if (gecen >= aralik) {
      _sonBildirim = DateTime.now();
      notifyListeners();
      return;
    }
    _bildirimZamani ??= Timer(aralik - gecen, () {
      _bildirimZamani = null;
      _sonBildirim = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _bildirimZamani?.cancel();
    super.dispose();
  }

  /// Kullanıcı yerelde bir değişiklik yaptığında çağrılır (senkron motoru bununla hemen göndermeyi dener).
  VoidCallback? yerelYazildi;

  // ------------------------------------------------------------------ okuma

  /// [durum]: yalnızca bu talep durumundakiler (null = hepsi). Arama Türkçe karakterleri katlar.
  Future<List<Talep>> liste({
    String arama = '',
    int limit = 50,
    int offset = 0,
    int? durum,
    TalepFiltre? filtre,
  }) async {
    final f = filtre ?? TalepFiltre(arama: arama, durumlar: {?durum});
    final k = _kosul(f);
    final rows = await _db.query(
      'talepler',
      where: k.where,
      whereArgs: k.args.isEmpty ? null : k.args,
      orderBy: switch (f.sirala) {
        TalepSirala.yeni =>
          'tarih DESC, COALESCE(no, 2147483647) DESC, yerel_id DESC',
        TalepSirala.eski =>
          'tarih ASC, COALESCE(no, 2147483647) ASC, yerel_id ASC',
        TalepSirala.ad =>
          'talep_eden COLLATE NOCASE ASC, COALESCE(no, 2147483647) DESC',
        TalepSirala.kayit => 'COALESCE(no, 2147483647) DESC, yerel_id DESC',
      },
      limit: limit,
      offset: offset,
    );
    return rows.map(Talep.new).toList();
  }

  /// Filtreyi SQL koşuluna çevirir. [durumlu] false ise durum seçimi yok sayılır (çip sayıları için).
  ({String where, List<Object?> args}) _kosul(
    TalepFiltre f, {
    bool durumlu = true,
  }) {
    final kosul = <String>['silindi = 0'];
    final arg = <Object?>[];
    final a = aramaMetni(f.arama);
    if (a.isNotEmpty) {
      // v7 gibi içerik ve kurumda da ara; "ara" sütunu ad, telefon, referans ve T.C. içerir.
      kosul.add('(ara LIKE ? OR icerik LIKE ? OR ilgili_kurum LIKE ?)');
      arg.addAll(['%$a%', '%${f.arama.trim()}%', '%${f.arama.trim()}%']);
    }
    if (durumlu && f.durumlar.isNotEmpty) {
      kosul.add('durum IN (${List.filled(f.durumlar.length, '?').join(',')})');
      arg.addAll(f.durumlar);
    }
    if (f.kategoriler.isNotEmpty) {
      kosul.add(
        'katno IN (${List.filled(f.kategoriler.length, '?').join(',')})',
      );
      arg.addAll(f.kategoriler);
    }
    if (f.ilce != null) {
      kosul.add('ilce = ?');
      arg.add(f.ilce);
    }
    if (f.kaydeden != null) {
      kosul.add('ekleyen = ?');
      arg.add(f.kaydeden);
    }
    final tel = f.telefon.replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.isNotEmpty) {
      kosul.add(
        "REPLACE(REPLACE(REPLACE(REPLACE(telefon,' ',''),'(',''),')',''),'-','') LIKE ?",
      );
      arg.add('%$tel%');
    }
    if (f.bas != null) {
      kosul.add('tarih >= ?');
      arg.add(f.bas);
    }
    if (f.bit != null) {
      kosul.add('tarih <= ?');
      arg.add(f.bit);
    }
    if (f.bekleyen) kosul.add('bekleyen = 1');
    if (f.hatirlatici) kosul.add('hatirlatici = 1');
    return (where: kosul.join(' AND '), args: arg);
  }

  /// Seçili durum hariç tüm filtreler uygulandığında her durumdaki kayıt sayısı (v7'deki çip sayıları).
  Future<Map<int, int>> durumSayilari(TalepFiltre f) async {
    final k = _kosul(f, durumlu: false);
    final r = await _db.rawQuery(
      'SELECT durum, COUNT(*) AS n FROM talepler WHERE ${k.where} GROUP BY durum',
      k.args,
    );
    return {for (final x in r) x['durum'] as int: x['n'] as int};
  }

  /// Filtreye uyan toplam kayıt sayısı.
  Future<int> sonucSayisi(TalepFiltre f) async {
    final k = _kosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM talepler WHERE ${k.where}',
            k.args,
          ),
        ) ??
        0;
  }

  /// Kayıtlarda geçen ilçeler (adı, önbellekteki il/ilçe listelerinden); en çok kayıtlı ilçe başta.
  Future<List<({int id, String ad, int adet})>> ilceSecenekleri() async {
    final r = await _db.rawQuery(
      'SELECT il, ilce, COUNT(*) AS n FROM talepler WHERE silindi = 0 AND ilce > 0 GROUP BY il, ilce',
    );
    final adlar = <int, String>{};
    final adet = <int, int>{};
    final iller = <int>{for (final x in r) (x['il'] as int?) ?? 0};
    for (final il in iller) {
      for (final o in await adresOku('ilce:$il') ?? const []) {
        adlar[(o as Map)['id'] as int] = o['ad'] as String;
      }
    }
    for (final x in r) {
      final id = x['ilce'] as int;
      adet[id] = (adet[id] ?? 0) + (x['n'] as int);
    }
    final cikti = [
      for (final e in adet.entries)
        (id: e.key, ad: adlar[e.key] ?? 'İlçe ${e.key}', adet: e.value),
    ]..sort((a, b) => b.adet.compareTo(a.adet));
    return cikti;
  }

  /// Sunucudaki yöneticiler ("Kaydeden" filtresi için); referans verisi inmediyse boş.
  Future<List<({int no, String adi})>> kaydedenler() async {
    final ek = await referansEk();
    return [
      for (final x in (ek['kaydedenler'] as List?) ?? const [])
        (no: (x as Map)['no'] as int, adi: x['adi'].toString()),
    ];
  }

  /// Sunucu numarasına karşılık gelen yerel kayıt (yoksa null): ana sayfadaki bloklardan ayrıntıya geçmek için.
  Future<int?> yerelIdNo(int no) async {
    final r = await _db.query(
      'talepler',
      columns: ['yerel_id'],
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['yerel_id'] as int?;
  }

  Future<Talep?> getir(int yerelId) async {
    final r = await _db.query(
      'talepler',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Talep(r.first);
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM talepler WHERE silindi = 0'),
      ) ??
      0;

  Future<Map<int, ({String adi, String? renk})>> durumlar() async => {
    for (final r in await _db.query('ref_durum'))
      r['no'] as int: (adi: r['adi'] as String, renk: r['renk'] as String?),
  };

  Future<Map<int, String>> kategoriler() async => {
    for (final r in await _db.query('ref_kategori', orderBy: 'adi'))
      r['no'] as int: r['adi'] as String,
  };

  // ------------------------------------------------------------------ yerel yazma (kuyruğa alır)

  /// Yeni talep ([yerelId] null) ya da var olanın düzenlenmesi. Değişiklik hemen yerelde görünür, kuyruğa yazılır.
  /// [ekstra]: sunucuda kayıtla birlikte işlenen, talep tablosunda tutulmayan seçenekler (SMS, rehbere kayıt, kara liste...).
  Future<int> kaydet(
    Map<String, Object?> alanlar, {
    int? yerelId,
    Map<String, Object?>? ekstra,
  }) async {
    final temiz = _hazirla({for (final a in talepAlanlari) a: alanlar[a]});
    final govde = jsonEncode({
      ...temiz,
      if (ekstra != null && ekstra.isNotEmpty) '_ekstra': ekstra,
    });
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      if (yerelId == null) {
        final satir = {
          ...temiz,
          'surum': 0,
          'bekleyen': 1,
          'silindi': 0,
          'ara': _ara(temiz),
        };
        id = await txn.insert('talepler', satir);
        await txn.insert('kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': id,
          'no': null,
          'taban': null,
          'govde': govde,
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': simdi,
        });
        return;
      }
      id = yerelId;
      final mevcut = (await txn.query(
        'talepler',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      await txn.update(
        'talepler',
        {...temiz, 'bekleyen': 1, 'ara': _ara(temiz)},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        // Aynı kayıt için bekleyen işlem varsa birleştir: sunucuya tek ve en güncel hal gider
        await txn.update(
          'kuyruk',
          {'govde': govde, 'durum': 'bekliyor', 'mesaj': ''},
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': yerelId,
          'no': mevcut['no'],
          'taban': mevcut['surum'],
          'govde': govde,
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': simdi,
          'onceki_json': jsonEncode(
            mevcut,
          ), // vazgeçilirse yerel kayıt bu haline döner
        });
      }
    });
    _bildir();
    yerelYazildi?.call();
    return id;
  }

  /// Talebi siler. Henüz sunucuya hiç gitmemişse yalnızca yerelden kalkar; aksi halde silme kuyruğa yazılır.
  Future<void> sil(int yerelId) async {
    final silinecekDosyalar = <String>[];
    await _db.transaction((txn) async {
      final r = await txn.query(
        'talepler',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      for (final d in await txn.query(
        'kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      )) {
        final yol = (jsonDecode(d['govde'] as String) as Map)['yol'];
        if (yol is String) silinecekDosyalar.add(yol);
      }
      await txn.delete(
        'kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(
          'talepler',
          where: 'yerel_id = ?',
          whereArgs: [yerelId],
        );
        return;
      }
      await txn.update(
        'talepler',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'sil',
          'yerel_id': yerelId,
          'no': no,
          'taban': null,
          'govde': '{}',
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
    for (final y in silinecekDosyalar) {
      try {
        await File(y).delete();
      } catch (_) {}
    }
    _bildir();
    yerelYazildi?.call();
  }

  // ------------------------------------------------------------------ ek dosyalar (kuyrukta bekleyen yüklemeler / silmeler)

  /// Cihazdaki bir dosyayı talebe eklenmek üzere kuyruğa alır (talep henüz sunucuda yoksa önce o gönderilir).
  Future<void> dosyaEkle(
    int yerelId, {
    required String yol,
    required String ad,
    required int boyut,
  }) async {
    final r = await _db.query(
      'talepler',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    await _db.insert('kuyruk', {
      'istemci_id': _uuid.v4(),
      'tur': 'dosya',
      'yerel_id': yerelId,
      'no': r.isEmpty ? null : r.first['no'],
      'taban': null,
      'govde': jsonEncode({'yol': yol, 'ad': ad, 'boyut': boyut}),
      'durum': 'bekliyor',
      'mesaj': '',
      'olusturma': DateTime.now().millisecondsSinceEpoch,
    });
    _bildir();
    yerelYazildi?.call();
  }

  /// Yerel kaydın sunucu numarası (henüz gönderilmediyse null).
  Future<int?> noBul(int yerelId) async {
    final r = await _db.query(
      'talepler',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    return r.isEmpty ? null : r.first['no'] as int?;
  }

  /// Bu talebe ait henüz gönderilmemiş dosyalar ve silinmeyi bekleyen sunucu dosyaları.
  Future<List<KuyrukOp>> dosyaIslemleri(int yerelId) async {
    final r = await _db.query(
      'kuyruk',
      where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
      whereArgs: [yerelId],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  /// Kuyruktaki bir dosya işlemini vazgeçer (yüklemeyse yerel kopya da silinir).
  Future<void> dosyaIsleminiIptalEt(KuyrukOp op) async {
    await _db.delete('kuyruk', where: 'id = ?', whereArgs: [op.id]);
    final yol = op.govde['yol'];
    if (op.tur == 'dosya' && yol is String) {
      try {
        await File(yol).delete();
      } catch (_) {}
    }
    _bildir();
  }

  /// Sunucudaki bir ek dosyanın silinmesini kuyruğa yazar.
  Future<void> sunucuDosyasiniSil(int yerelId, int no, String ad) async {
    await _db.insert('kuyruk', {
      'istemci_id': _uuid.v4(),
      'tur': 'dosya_sil',
      'yerel_id': yerelId,
      'no': no,
      'taban': null,
      'govde': jsonEncode({'ad': ad}),
      'durum': 'bekliyor',
      'mesaj': '',
      'olusturma': DateTime.now().millisecondsSinceEpoch,
    });
    _bildir();
    yerelYazildi?.call();
  }

  // ------------------------------------------------------------------ ayrıntı ve adres önbelleği

  Future<void> ekYaz(int no, Map<String, dynamic> ek) async {
    await _db.insert('talep_ek', {
      'no': no,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(int no) async {
    final r = await _db.query('talep_ek', where: 'no = ?', whereArgs: [no]);
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  Future<List<dynamic>?> adresOku(String anahtar) async {
    final r = await _db.query(
      'adres_onbellek',
      where: 'anahtar = ?',
      whereArgs: [anahtar],
    );
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as List<dynamic>;
  }

  Future<void> adresYaz(String anahtar, List<dynamic> liste) =>
      _db.insert('adres_onbellek', {
        'anahtar': anahtar,
        'json': jsonEncode(liste),
        'zaman': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Yerel verideki öneriler (çevrimdışı ya da hızlı otomatik tamamlama): ad+telefon, referans+telefon, kurum.
  Future<List<Map<String, Object?>>> yerelOneriler(
    String tur,
    String kelime, {
    int limit = 8,
  }) async {
    final k = '%${kelime.trim()}%';
    switch (tur) {
      case 'kisi':
        return _db.rawQuery(
          'SELECT DISTINCT talep_eden AS ad, telefon FROM talepler WHERE silindi = 0 AND talep_eden LIKE ? ORDER BY talep_eden LIMIT ?',
          [k, limit],
        );
      case 'referans':
        return _db.rawQuery(
          "SELECT DISTINCT referans AS ad, referans_telefon AS telefon FROM talepler WHERE silindi = 0 AND referans <> '' AND referans LIKE ? ORDER BY referans LIMIT ?",
          [k, limit],
        );
      default:
        return _db.rawQuery(
          "SELECT DISTINCT ilgili_kurum AS ad FROM talepler WHERE silindi = 0 AND ilgili_kurum <> '' AND ilgili_kurum LIKE ? ORDER BY ilgili_kurum LIMIT ?",
          [k, limit],
        );
    }
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  /// Gönderilmeyi bekleyen + sorunlu (çakışma/hata) işlem sayısı.
  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuTalep,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'talepler',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuTalep != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(Talep.apiden(sunucuTalep));
        await txn.update(
          'talepler',
          {...s, 'ara': _ara(s), 'bekleyen': kalan > 0 ? 1 : 0},
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  Future<void> islemSorunlu(
    KuyrukOp op,
    String durum,
    String mesaj, {
    Map<String, dynamic>? sunucu,
  }) async {
    await _db.update(
      'kuyruk',
      {
        'durum': durum,
        'mesaj': mesaj,
        'sunucu_json': sunucu == null ? null : jsonEncode(sunucu),
      },
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  /// Çakışmada sunucudaki sürümü kabul et: yerel değişiklik atılır.
  Future<void> cakismaSunucuyuAl(KuyrukOp op) async {
    final sunucu = op.sunucu;
    await _db.transaction((txn) async {
      await txn.delete('kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(Talep.apiden(sunucu));
        await txn.update(
          'talepler',
          {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0},
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  /// Çakışmada kendi sürümünü gönder: taban sunucunun sürümüne çekilir, işlem yeniden kuyruğa girer.
  Future<void> cakismaBenimkiniGonder(KuyrukOp op) async {
    final surum = (op.sunucu?['surum'] as num?)?.toInt() ?? op.taban;
    await _db.update(
      'kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  /// Hatalı (ör. doğrulama) bir işlemi vazgeçerek yerel değişikliği sunucudaki haline döndürmek için kuyruktan kaldırır.
  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('kuyruk', where: 'id = ?', whereArgs: [op.id]);
      final no = op.no;
      if (no == null) {
        await txn.delete(
          'talepler',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        // Düzenleme öncesi hale dön (yoksa yalnızca bayrakları temizle)
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [...talepAlanlari, ...saltOkunur, 'surum', 'ara']) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'talepler',
          geri,
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  // ------------------------------------------------------------------ sunucudan gelenler

  /// Sunucudan gelen talepleri yerele işler. Yerelde gönderilmemiş değişikliği olan kayıtlar EZİLMEZ.
  Future<void> sunucudanYaz(
    List<Map<String, dynamic>> talepler,
    List<int> silinenler,
  ) async {
    if (talepler.isEmpty && silinenler.isEmpty) return;
    await _db.transaction((txn) async {
      // Not: UPSERT (ON CONFLICT DO UPDATE) eski Android SQLite sürümlerinde (< 3.24) yok; güncelle-yoksa-ekle kullanılır.
      for (final t in talepler) {
        final no = (t['no'] as num).toInt();
        final s = _hazirla(Talep.apiden(t));
        final satir = {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0};
        // Yerel bekleyen değişiklik varsa dokunma (güncelleme 0 satır etkiler, ekleme UNIQUE nedeniyle yok sayılır)
        final guncellenen = await txn.update(
          'talepler',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'talepler',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'talepler',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  /// Sunucunun görebildiği no listesinde olmayan, gönderilmemiş değişikliği bulunmayan yerel kayıtları siler.
  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'talepler',
      columns: ['no'],
      where: 'no IS NOT NULL AND bekleyen = 0',
    );
    final fazla = [
      for (final r in yerel)
        if (!sunucuIdleri.contains(r['no'] as int)) r['no'] as int,
    ];
    for (var i = 0; i < fazla.length; i += 500) {
      final parca = fazla.skip(i).take(500).toList();
      await _db.delete(
        'talepler',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  Future<void> referansYaz({
    required List<Map<String, dynamic>> durumlar,
    required List<Map<String, dynamic>> kategoriler,
    Map<String, dynamic>? ek,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('ref_durum');
      await txn.delete('ref_kategori');
      for (final d in durumlar) {
        await txn.insert('ref_durum', {
          'no': d['no'],
          'adi': d['adi'],
          'renk': d['renk'],
        });
      }
      for (final k in kategoriler) {
        await txn.insert('ref_kategori', {'no': k['no'], 'adi': k['adi']});
      }
    });
    if (ek != null) await metaYaz('referans_ek', jsonEncode(ek));
    _bildir();
  }

  /// Rehber kategorileri, varsayılan il, SMS hazır mı.
  Future<Map<String, dynamic>> referansEk() async {
    final s = await meta('referans_ek');
    return s == null ? {} : jsonDecode(s) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ meta

  Future<String?> meta(String anahtar) async {
    final r = await _db.query(
      'meta',
      where: 'anahtar = ?',
      whereArgs: [anahtar],
    );
    return r.isEmpty ? null : r.first['deger'] as String?;
  }

  Future<void> metaYaz(String anahtar, String? deger) async {
    if (deger == null) {
      await _db.delete('meta', where: 'anahtar = ?', whereArgs: [anahtar]);
    } else {
      await _db.insert('meta', {
        'anahtar': anahtar,
        'deger': deger,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Tam yeniden yükleme için: gönderilmemiş değişikliği olmayan tüm sunucu kayıtlarını ve imleci sıfırlar.
  Future<void> imleciSifirla() => metaYaz('imlec', null);
}
