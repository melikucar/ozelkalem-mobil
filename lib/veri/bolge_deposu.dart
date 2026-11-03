import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'bolge.dart';
import 'talep_deposu.dart' show KuyrukOp;
import 'yazi_formatlari.dart';
import 'yerel_db.dart';

/// Bölge bilgileri için yerel veri erişimi + giden kuyruk (tablolar `bolgeler`, `bl_kuyruk`).
/// Bilgi alanları tek bir JSON sütununda (`veri`) tutulur; liste için gereken ilçe/semt/mahalle ve arama metni ayrı sütunlardır.
class BolgeDeposu extends ChangeNotifier {
  BolgeDeposu(this._yerel);

  final YerelDb _yerel;
  Database get _db => _yerel.db;

  static const _uuid = Uuid();

  /// Kullanıcı yerelde bir değişiklik yaptığında çağrılır (senkron motoru hemen göndermeyi dener).
  VoidCallback? yerelYazildi;

  void _bildir() => notifyListeners();

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

  // ------------------------------------------------------------------ okuma

  (String, List<Object?>) _kosul(BolgeFiltre f) {
    final k = <String>['silindi = 0'];
    final a = <Object?>[];
    if (f.ilce != 0) {
      k.add('ilce = ?');
      a.add(f.ilce);
    }
    final kelime = aramaMetni(f.kelime);
    if (kelime.isNotEmpty) {
      k.add('ara LIKE ?');
      a.add('%$kelime%');
    }
    return (k.join(' AND '), a);
  }

  Future<List<Bolge>> liste(
    BolgeFiltre f, {
    int limit = 40,
    int offset = 0,
  }) async {
    final (where, args) = _kosul(f);
    final r = await _db.query(
      'bolgeler',
      where: where,
      whereArgs: args,
      // `ara` ilçe > semt > mahalle sırasıyla Türkçe harfleri katlanmış metindir: SQLite'ın ç/ş/ğ sıralaması bozuk olduğundan buna göre dizilir
      orderBy: 'ara, yerel_id',
      limit: limit,
      offset: offset,
    );
    return r.map(Bolge.new).toList();
  }

  Future<int> sonucSayisi(BolgeFiltre f) async {
    final (where, args) = _kosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM bolgeler WHERE $where',
            args,
          ),
        ) ??
        0;
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM bolgeler WHERE silindi = 0'),
      ) ??
      0;

  /// Ilçe süzgeci için {ilçe no, ad, adet}.
  Future<List<({int ilce, String ad, int adet})>> ilceler() async {
    final r = await _db.rawQuery(
      'SELECT ilce, ilce_adi, COUNT(*) c FROM bolgeler WHERE silindi = 0 GROUP BY ilce',
    );
    final l = [
      for (final x in r)
        (
          ilce: x['ilce'] as int,
          ad: (x['ilce_adi'] ?? '') as String,
          adet: x['c'] as int,
        ),
    ];
    l.sort((a, b) => aramaMetni(a.ad).compareTo(aramaMetni(b.ad)));
    return l;
  }

  /// Üst kutular: toplam bölge, toplam nüfus, ortalama doluluk.
  Future<({int toplam, int nufus, double doluluk})> ozet(BolgeFiltre f) async {
    final (where, args) = _kosul(f);
    final r = await _db.query('bolgeler', where: where, whereArgs: args);
    var nufus = 0;
    var toplamDoluluk = 0.0;
    for (final x in r) {
      final b = Bolge(x);
      nufus +=
          int.tryParse(b.alan('toplam_nufus').replaceAll(RegExp(r'\D'), '')) ??
          0;
      toplamDoluluk += b.doluluk;
    }
    return (
      toplam: r.length,
      nufus: nufus,
      doluluk: r.isEmpty ? 0.0 : toplamDoluluk / r.length,
    );
  }

  Future<Bolge?> getir(int yerelId) async {
    final r = await _db.query(
      'bolgeler',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Bolge(r.first);
  }

  Future<int?> noBul(int yerelId) async {
    final r = await _db.query(
      'bolgeler',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    return r.isEmpty ? null : r.first['no'] as int?;
  }

  // ------------------------------------------------------------------ yazma (kuyruğa alır)

  /// Yeni kayıt ([yerelId] null) ya da düzenleme. [alanlar]: ilce/semt/mahalle (no) + bilgi alanları (metin).
  /// [adlar]: seçilen ilçe/semt/mahalle adları (yerelde listede görünsün diye).
  Future<int> kaydet(
    Map<String, Object?> alanlar, {
    required Map<String, String> adlar,
    int? yerelId,
    int il = 0,
  }) async {
    final gonderilecek = {
      for (final a in [...bolgeAdresAnahtarlari, ...bolgeBilgiAnahtarlari])
        if (alanlar.containsKey(a)) a: alanlar[a],
    };
    final govde = jsonEncode(gonderilecek);
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      final mevcutSatir = yerelId == null
          ? null
          : (await txn.query(
              'bolgeler',
              where: 'yerel_id = ?',
              whereArgs: [yerelId],
            )).first;
      final eskiBilgi = mevcutSatir == null
          ? <String, String>{}
          : Bolge(mevcutSatir).bilgi;
      final yeniBilgi = {
        ...eskiBilgi,
        for (final k in bolgeBilgiAnahtarlari)
          if (alanlar.containsKey(k)) k: '${alanlar[k] ?? ''}'.trim(),
      };
      final yerel = <String, Object?>{
        'il': mevcutSatir?['il'] ?? il,
        'ilce': (alanlar['ilce'] as num?)?.toInt() ?? 0,
        'semt': (alanlar['semt'] as num?)?.toInt() ?? 0,
        'mahalle': (alanlar['mahalle'] as num?)?.toInt() ?? 0,
        'ilce_adi': adlar['ilce'] ?? '',
        'semt_adi': adlar['semt'] ?? '',
        'mahalle_adi': adlar['mahalle'] ?? '',
        'veri': jsonEncode(yeniBilgi),
        'bekleyen': 1,
        'silindi': 0,
      };
      yerel['ara'] = Bolge.aramaMetniUret(yerel);
      if (yerelId == null) {
        id = await txn.insert('bolgeler', {
          ...yerel,
          'surum': 0,
          'tarih': DateTime.now().toIso8601String().substring(0, 19),
        });
        await txn.insert('bl_kuyruk', {
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
      await txn.update(
        'bolgeler',
        yerel,
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'bl_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        final eski = jsonDecode(op.first['govde'] as String) as Map;
        await txn.update(
          'bl_kuyruk',
          {
            'govde': jsonEncode({...eski, ...gonderilecek}),
            'durum': 'bekliyor',
            'mesaj': '',
          },
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('bl_kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': yerelId,
          'no': mevcutSatir!['no'],
          'taban': mevcutSatir['surum'],
          'govde': govde,
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': simdi,
          'onceki_json': jsonEncode(mevcutSatir),
        });
      }
    });
    _bildir();
    yerelYazildi?.call();
    return id;
  }

  Future<void> sil(int yerelId) async {
    await _db.transaction((txn) async {
      final r = await txn.query(
        'bolgeler',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'bl_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(
          'bolgeler',
          where: 'yerel_id = ?',
          whereArgs: [yerelId],
        );
        return;
      }
      await txn.update(
        'bolgeler',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'bl_kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('bl_kuyruk', {
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
    _bildir();
    yerelYazildi?.call();
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'bl_kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM bl_kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('bl_kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuBolge,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('bl_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'bolgeler',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuBolge != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM bl_kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = Bolge.apiden(sunucuBolge);
        await txn.update(
          'bolgeler',
          {...s, 'ara': Bolge.aramaMetniUret(s), 'bekleyen': kalan > 0 ? 1 : 0},
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
      'bl_kuyruk',
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

  Future<void> cakismaSunucuyuAl(KuyrukOp op) async {
    final sunucu = op.sunucu;
    await _db.transaction((txn) async {
      await txn.delete('bl_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = Bolge.apiden(sunucu);
        await txn.update(
          'bolgeler',
          {...s, 'ara': Bolge.aramaMetniUret(s), 'bekleyen': 0, 'silindi': 0},
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  Future<void> cakismaBenimkiniGonder(KuyrukOp op) async {
    final surum = (op.sunucu?['surum'] as num?)?.toInt() ?? op.taban;
    await _db.update(
      'bl_kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('bl_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          'bolgeler',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [
            'il',
            'ilce',
            'semt',
            'mahalle',
            'ilce_adi',
            'semt_adi',
            'mahalle_adi',
            'veri',
            'surum',
            'ara',
          ]) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'bolgeler',
          geri,
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  // ------------------------------------------------------------------ sunucudan gelenler

  /// Yerelde gönderilmemiş değişikliği olanlar EZİLMEZ.
  Future<void> sunucudanYaz(
    List<Map<String, dynamic>> kayitlar,
    List<int> silinenler,
  ) async {
    if (kayitlar.isEmpty && silinenler.isEmpty) return;
    await _db.transaction((txn) async {
      for (final p in kayitlar) {
        final no = (p['no'] as num).toInt();
        final s = Bolge.apiden(p);
        final satir = {
          ...s,
          'ara': Bolge.aramaMetniUret(s),
          'bekleyen': 0,
          'silindi': 0,
        };
        final guncellenen = await txn.update(
          'bolgeler',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'bolgeler',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'bolgeler',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'bolgeler',
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
        'bolgeler',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('bl_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('bl_referans');
    return s == null ? {} : jsonDecode(s) as Map<String, dynamic>;
  }

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
}
