import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'faaliyet.dart' show duzdenHtml;
import 'talep_deposu.dart' show KuyrukOp;
import 'tbmm.dart';
import 'yazi_formatlari.dart';
import 'yerel_db.dart';

/// TBMM (kanun teklifi, soru ve araştırma önergeleri) için yerel veri erişimi + giden kuyruk (tablolar `tbmm`, `tb_kuyruk`, `tbmm_ek`).
class TbmmDeposu extends ChangeNotifier {
  TbmmDeposu(this._yerel);

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
    '${m['adi'] ?? ''} ${htmlDuz('${m['icerik'] ?? ''}')} ${m['notlar'] ?? ''}',
  );

  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in ['adi', 'tarih', 'icerik', 'notlar']) {
      if (r.containsKey(k)) r[k] = (r[k] ?? '').toString();
    }
    for (final k in ['tablo', 'ekleyen', 'ek']) {
      if (r.containsKey(k)) r[k] = (r[k] as num?)?.toInt() ?? 0;
    }
    return r;
  }

  // ------------------------------------------------------------------ okuma

  (String, List<Object?>) _kosul(TbmmFiltre f) {
    final k = <String>['silindi = 0'];
    final a = <Object?>[];
    if (f.tablo != 0) {
      k.add('tablo = ?');
      a.add(f.tablo);
    }
    final kelime = aramaMetni(f.kelime);
    if (kelime.isNotEmpty) {
      k.add('ara LIKE ?');
      a.add('%$kelime%');
    }
    return (k.join(' AND '), a);
  }

  Future<List<Tbmm>> liste(
    TbmmFiltre f, {
    int limit = 40,
    int offset = 0,
  }) async {
    final (where, args) = _kosul(f);
    final r = await _db.query(
      'tbmm',
      where: where,
      whereArgs: args,
      orderBy: 'tarih DESC, COALESCE(no, 2147483647) DESC, yerel_id DESC',
      limit: limit,
      offset: offset,
    );
    return r.map(Tbmm.new).toList();
  }

  Future<int> sonucSayisi(TbmmFiltre f) async {
    final (where, args) = _kosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM tbmm WHERE $where', args),
        ) ??
        0;
  }

  /// Her türdeki kayıt sayısı (sekme rozetleri): {tablo: adet}.
  Future<Map<int, int>> turSayilari() async {
    final r = await _db.rawQuery(
      'SELECT tablo, COUNT(*) c FROM tbmm WHERE silindi = 0 GROUP BY tablo',
    );
    return {for (final x in r) x['tablo'] as int: x['c'] as int};
  }

  /// Seçili türün (0: hepsi) özeti (web'deki dört kutu): toplam, bu ay, bu yıl, son kayıt tarihi.
  Future<({int toplam, int buAy, int buYil, String? son})> ozet(
    int tablo,
  ) async {
    final n = DateTime.now();
    final ay = tbmmTarihYaz(DateTime(n.year, n.month, 1));
    final yil = tbmmTarihYaz(DateTime(n.year, 1, 1));
    final r = await _db.rawQuery(
      'SELECT COUNT(*) c, COALESCE(SUM(tarih >= ?), 0) ay, COALESCE(SUM(tarih >= ?), 0) yil, MAX(tarih) son FROM tbmm WHERE silindi = 0${tablo == 0 ? '' : ' AND tablo = ?'}',
      [ay, yil, if (tablo != 0) tablo],
    );
    final x = r.first;
    return (
      toplam: x['c'] as int,
      buAy: (x['ay'] as num).toInt(),
      buYil: (x['yil'] as num).toInt(),
      son: x['son'] as String?,
    );
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM tbmm WHERE silindi = 0'),
      ) ??
      0;

  Future<Tbmm?> getir(int yerelId) async {
    final r = await _db.query(
      'tbmm',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Tbmm(r.first);
  }

  Future<int?> noBul(int yerelId) async {
    final r = await _db.query(
      'tbmm',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    return r.isEmpty ? null : r.first['no'] as int?;
  }

  Future<Tbmm?> noIle(int no) async {
    final r = await _db.query(
      'tbmm',
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : Tbmm(r.first);
  }

  // ------------------------------------------------------------------ yazma (kuyruğa alır)

  /// Yeni kayıt ([yerelId] null) ya da düzenleme. `icerik` yalnızca değiştiyse [alanlar]'a konur (düz metin).
  Future<int> kaydet(Map<String, Object?> alanlar, {int? yerelId}) async {
    final gonderilecek = {
      for (final a in tbmmAlanlari)
        if (alanlar.containsKey(a)) a: alanlar[a],
    };
    final yerel = Map<String, Object?>.from(gonderilecek);
    if (yerel.containsKey('icerik')) {
      yerel['icerik'] = duzdenHtml('${yerel['icerik'] ?? ''}');
    }
    final temiz = _hazirla(yerel);
    final govde = jsonEncode(_hazirla(gonderilecek));
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      if (yerelId == null) {
        id = await txn.insert('tbmm', {
          ...temiz,
          'surum': 0,
          'bekleyen': 1,
          'silindi': 0,
          'ara': _ara(temiz),
        });
        await txn.insert('tb_kuyruk', {
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
        'tbmm',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      final birlesik = {...mevcut, ...temiz};
      await txn.update(
        'tbmm',
        {...temiz, 'bekleyen': 1, 'ara': _ara(birlesik)},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'tb_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        final eski = jsonDecode(op.first['govde'] as String) as Map;
        await txn.update(
          'tb_kuyruk',
          {
            'govde': jsonEncode({...eski, ..._hazirla(gonderilecek)}),
            'durum': 'bekliyor',
            'mesaj': '',
          },
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('tb_kuyruk', {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': yerelId,
          'no': mevcut['no'],
          'taban': mevcut['surum'],
          'govde': govde,
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
    final silinecekDosyalar = <String>[];
    await _db.transaction((txn) async {
      final r = await txn.query(
        'tbmm',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'tb_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      for (final d in await txn.query(
        'tb_kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      )) {
        final yol = (jsonDecode(d['govde'] as String) as Map)['yol'];
        if (yol is String) silinecekDosyalar.add(yol);
      }
      await txn.delete(
        'tb_kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete('tbmm', where: 'yerel_id = ?', whereArgs: [yerelId]);
        return;
      }
      await txn.update(
        'tbmm',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'tb_kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('tb_kuyruk', {
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

  // ------------------------------------------------------------------ ek dosyalar

  Future<void> dosyaEkle(
    int yerelId, {
    required String yol,
    required String ad,
    required int boyut,
  }) async {
    await _db.insert('tb_kuyruk', {
      'istemci_id': _uuid.v4(),
      'tur': 'dosya',
      'yerel_id': yerelId,
      'no': await noBul(yerelId),
      'taban': null,
      'govde': jsonEncode({'yol': yol, 'ad': ad, 'boyut': boyut}),
      'durum': 'bekliyor',
      'mesaj': '',
      'olusturma': DateTime.now().millisecondsSinceEpoch,
    });
    _bildir();
    yerelYazildi?.call();
  }

  Future<List<KuyrukOp>> dosyaIslemleri(int yerelId) async {
    final r = await _db.query(
      'tb_kuyruk',
      where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
      whereArgs: [yerelId],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<void> dosyaIsleminiIptalEt(KuyrukOp op) async {
    await _db.delete('tb_kuyruk', where: 'id = ?', whereArgs: [op.id]);
    final yol = op.govde['yol'];
    if (op.tur == 'dosya' && yol is String) {
      try {
        await File(yol).delete();
      } catch (_) {}
    }
    _bildir();
  }

  Future<void> sunucuDosyasiniSil(int yerelId, int no, String ad) async {
    await _db.insert('tb_kuyruk', {
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

  // ------------------------------------------------------------------ ayrıntı önbelleği

  Future<void> ekYaz(int no, Map<String, dynamic> ek) async {
    await _db.insert('tbmm_ek', {
      'no': no,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // liste rozeti için ek sayısı da güncellenir
    final n = (ek['dosyalar'] as List?)?.length;
    if (n != null) {
      await _db.update(
        'tbmm',
        {'ek': n},
        where: 'no = ? AND ek != ?',
        whereArgs: [no, n],
      );
    }
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(int no) async {
    final r = await _db.query('tbmm_ek', where: 'no = ?', whereArgs: [no]);
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'tb_kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM tb_kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('tb_kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuTbmm,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('tb_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'tbmm',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuTbmm != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM tb_kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(Tbmm.apiden(sunucuTbmm));
        await txn.update(
          'tbmm',
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
      'tb_kuyruk',
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
      await txn.delete('tb_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(Tbmm.apiden(sunucu));
        await txn.update(
          'tbmm',
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
      'tb_kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('tb_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          'tbmm',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [...tbmmAlanlari, 'surum', 'ara']) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'tbmm',
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
        final s = _hazirla(Tbmm.apiden(p));
        final satir = {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0};
        final guncellenen = await txn.update(
          'tbmm',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'tbmm',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'tbmm',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'tbmm',
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
        'tbmm',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('tb_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('tb_referans');
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
