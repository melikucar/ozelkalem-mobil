import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'faaliyet.dart' show duzdenHtml;
import 'program.dart' show programZamanYaz;
import 'talep_deposu.dart' show KuyrukOp;
import 'yazi_formatlari.dart';
import 'yazisma.dart';
import 'yerel_db.dart';

/// Yazışmalar için yerel veri erişimi + giden kuyruk (programlar ile aynı mantık; tablolar `yazismalar`, `y_kuyruk`, `yazisma_ek`).
class YazismaDeposu extends ChangeNotifier {
  YazismaDeposu(this._yerel);

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

  static String _ara(Map<String, Object?> m) => aramaMetni(
    '${m['kisi'] ?? ''} ${m['unvan'] ?? ''} ${m['talep_adi'] ?? ''} ${htmlDuz('${m['icerik'] ?? ''}')}',
  );

  static const _metinler = [
    'talep_eden',
    'talep_adi',
    'kisi',
    'unvan',
    'icerik',
    'tarih',
  ];
  static const _sayilar = [
    'logo',
    'imza',
    'imza_unvan',
    'imza_unvan_2',
    'alt_yazi',
    'ekleyen',
  ];

  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in _metinler) {
      if (r.containsKey(k)) r[k] = (r[k] ?? '').toString();
    }
    for (final k in _sayilar) {
      if (r.containsKey(k)) {
        final d = r[k];
        r[k] = d is bool ? (d ? 1 : 0) : (d as num?)?.toInt() ?? 0;
      }
    }
    return r;
  }

  // ------------------------------------------------------------------ okuma

  (String, List<Object?>) _kosul(YazismaFiltre f) {
    final k = <String>['silindi = 0'];
    final a = <Object?>[];
    if (f.kaydeden != 0) {
      k.add('ekleyen = ?');
      a.add(f.kaydeden);
    }
    if (f.kisi.isNotEmpty) {
      k.add('kisi = ?');
      a.add(f.kisi);
    }
    final gun = f.donem.gun;
    if (gun != null) {
      k.add('tarih >= ?');
      a.add(programZamanYaz(DateTime.now().subtract(Duration(days: gun))));
    }
    final kelime = aramaMetni(f.kelime);
    if (kelime.isNotEmpty) {
      k.add('ara LIKE ?');
      a.add('%$kelime%');
    }
    return (k.join(' AND '), a);
  }

  Future<List<Yazisma>> liste(
    YazismaFiltre f, {
    int limit = 40,
    int offset = 0,
  }) async {
    final (where, args) = _kosul(f);
    final r = await _db.query(
      'yazismalar',
      where: where,
      whereArgs: args,
      orderBy: 'tarih DESC, COALESCE(no, 2147483647) DESC, yerel_id DESC',
      limit: limit,
      offset: offset,
    );
    return r.map(Yazisma.new).toList();
  }

  Future<int> sonucSayisi(YazismaFiltre f) async {
    final (where, args) = _kosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM yazismalar WHERE $where',
            args,
          ),
        ) ??
        0;
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM yazismalar WHERE silindi = 0'),
      ) ??
      0;

  /// "En çok yazı yazılan kişiler" (web'deki kutu).
  Future<List<({String kisi, int adet})>> enCokYazilanlar({
    int limit = 12,
  }) async {
    final r = await _db.rawQuery(
      "SELECT kisi, COUNT(*) c FROM yazismalar WHERE silindi = 0 AND kisi != '' GROUP BY kisi ORDER BY c DESC, kisi LIMIT ?",
      [limit],
    );
    return [
      for (final x in r) (kisi: x['kisi'] as String, adet: x['c'] as int),
    ];
  }

  Future<Yazisma?> getir(int yerelId) async {
    final r = await _db.query(
      'yazismalar',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Yazisma(r.first);
  }

  Future<int?> noBul(int yerelId) async {
    final r = await _db.query(
      'yazismalar',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    return r.isEmpty ? null : r.first['no'] as int?;
  }

  Future<Yazisma?> noIle(int no) async {
    final r = await _db.query(
      'yazismalar',
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : Yazisma(r.first);
  }

  // ------------------------------------------------------------------ yazma

  /// [metin]: kullanıcının yazdığı DÜZ metin; verilirse yerelde paragraf HTML'ine çevrilir ve sunucuya düz metin olarak gider.
  /// Verilmezse (güncellemede) mevcut biçimli içerik korunur.
  Future<int> kaydet(
    Map<String, Object?> alanlar, {
    int? yerelId,
    String? metin,
  }) async {
    final temiz = _hazirla(alanlar);
    final gonderilecek = <String, Object?>{
      for (final k in yazismaAlanlari)
        if (temiz.containsKey(k)) k: temiz[k],
    };
    if (metin != null) {
      temiz['icerik'] = duzdenHtml(metin);
      gonderilecek['icerik'] = metin.trim();
      gonderilecek['icerik_duz'] = 1;
    }
    final simdi = DateTime.now().millisecondsSinceEpoch;
    late int id;
    await _db.transaction((txn) async {
      if (yerelId == null) {
        final satir = {
          'logo': 1,
          'imza': 1,
          'imza_unvan': 1,
          'imza_unvan_2': 1,
          'alt_yazi': 1,
          ...temiz,
          'tarih': programZamanYaz(DateTime.now()),
          'surum': 0,
          'bekleyen': 1,
          'silindi': 0,
        };
        id = await txn.insert('yazismalar', {...satir, 'ara': _ara(satir)});
        await txn.insert('y_kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': id,
          'no': null,
          'taban': null,
          'govde': jsonEncode({
            'logo': 1,
            'imza': 1,
            'imza_unvan': 1,
            'imza_unvan_2': 1,
            'alt_yazi': 1,
            ...gonderilecek,
          }),
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': simdi,
        });
        return;
      }
      id = yerelId;
      final mevcut = (await txn.query(
        'yazismalar',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      final birlesik = {...mevcut, ...temiz};
      await txn.update(
        'yazismalar',
        {...temiz, 'bekleyen': 1, 'ara': _ara(birlesik)},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'y_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        final eski = jsonDecode(op.first['govde'] as String) as Map;
        await txn.update(
          'y_kuyruk',
          {
            'govde': jsonEncode({...eski, ...gonderilecek}),
            'durum': 'bekliyor',
            'mesaj': '',
          },
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('y_kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': yerelId,
          'no': mevcut['no'],
          'taban': mevcut['surum'],
          'govde': jsonEncode({
            for (final k in yazismaAlanlari) k: birlesik[k],
            ...gonderilecek,
          }),
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': simdi,
          'onceki_json': jsonEncode(mevcut),
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
        'yazismalar',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'y_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(
          'yazismalar',
          where: 'yerel_id = ?',
          whereArgs: [yerelId],
        );
        return;
      }
      await txn.update(
        'yazismalar',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'y_kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('y_kuyruk', {
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

  // ------------------------------------------------------------------ ayrıntı önbelleği

  Future<void> ekYaz(int no, Map<String, dynamic> ek) async {
    await _db.insert('yazisma_ek', {
      'no': no,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(int no) async {
    final r = await _db.query('yazisma_ek', where: 'no = ?', whereArgs: [no]);
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'y_kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM y_kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('y_kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuYazisma,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('y_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'yazismalar',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuYazisma != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM y_kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(Yazisma.apiden(sunucuYazisma));
        await txn.update(
          'yazismalar',
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
      'y_kuyruk',
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
      await txn.delete('y_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(Yazisma.apiden(sunucu));
        await txn.update(
          'yazismalar',
          {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0},
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
      'y_kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('y_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          'yazismalar',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [
            ...yazismaAlanlari,
            'icerik',
            'talep_adi',
            'surum',
            'ara',
          ]) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'yazismalar',
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
    List<Map<String, dynamic>> yazismalar,
    List<int> silinenler,
  ) async {
    if (yazismalar.isEmpty && silinenler.isEmpty) return;
    await _db.transaction((txn) async {
      for (final p in yazismalar) {
        final no = (p['no'] as num).toInt();
        final s = _hazirla(Yazisma.apiden(p));
        final satir = {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0};
        final guncellenen = await txn.update(
          'yazismalar',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'yazismalar',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'yazismalar',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'yazismalar',
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
        'yazismalar',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('y_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('y_referans');
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
