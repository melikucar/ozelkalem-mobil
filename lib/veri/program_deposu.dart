import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'yazi_formatlari.dart';
import 'program.dart';
import 'talep_deposu.dart' show KuyrukOp;
import 'yerel_db.dart';

/// Programlar (ajanda takvimi) için yerel veri erişimi + giden kuyruk. Talepler ile aynı mantık, ayrı tablolar:
/// `programlar`, `p_kuyruk`, `program_ek`. Ekranlar yalnızca bunu okur; ağ yalnızca senkron içindir.
class ProgramDeposu extends ChangeNotifier {
  ProgramDeposu(this._yerel);

  final YerelDb _yerel;
  Database get _db => _yerel.db;

  static const _uuid = Uuid();

  /// Kullanıcı yerelde bir değişiklik yaptığında çağrılır (senkron motoru hemen göndermeyi dener).
  VoidCallback? yerelYazildi;

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

  static String _ara(Map<String, Object?> m) =>
      aramaMetni('${m['adi'] ?? ''} ${m['yer'] ?? ''}');

  /// Alanları yerel şemaya uygun hale getirir.
  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in ['adi', 'yer', 'notlar', 'renk', 'tarih1', 'tarih2']) {
      if (r.containsKey(k)) r[k] = (r[k] ?? '').toString();
    }
    if (r.containsKey('randevu_no')) {
      r['randevu_no'] = (r['randevu_no'] as num?)?.toInt() ?? 0;
    }
    return r;
  }

  // ------------------------------------------------------------------ okuma

  /// [bas, bit) aralığıyla kesişen programlar (başlangıca göre). Silinmeyi bekleyenler gösterilmez.
  Future<List<Program>> aralik(DateTime bas, DateTime bit) async {
    final b = programZamanYaz(bas);
    final e = programZamanYaz(bit);
    final r = await _db.rawQuery(
      'SELECT * FROM programlar WHERE silindi = 0 AND tarih1 < ? AND MAX(tarih1, tarih2) >= ? ORDER BY tarih1, tarih2, yerel_id',
      [e, b],
    );
    return r.map(Program.new).toList();
  }

  /// Ad ve yerde arama (Türkçe karakterleri katlar), en yakın tarihe göre.
  Future<List<Program>> ara(String kelime, {int limit = 100}) async {
    final a = aramaMetni(kelime);
    if (a.isEmpty) return [];
    final r = await _db.query(
      'programlar',
      where: 'silindi = 0 AND ara LIKE ?',
      whereArgs: ['%$a%'],
      orderBy: 'tarih1 DESC',
      limit: limit,
    );
    return r.map(Program.new).toList();
  }

  Future<Program?> getir(int yerelId) async {
    final r = await _db.query(
      'programlar',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Program(r.first);
  }

  Future<int?> yerelIdNo(int no) async {
    final r = await _db.query(
      'programlar',
      columns: ['yerel_id'],
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['yerel_id'] as int?;
  }

  Future<int?> noBul(int yerelId) async {
    final r = await _db.query(
      'programlar',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    return r.isEmpty ? null : r.first['no'] as int?;
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM programlar WHERE silindi = 0'),
      ) ??
      0;

  // ------------------------------------------------------------------ yerel yazma (kuyruğa alır)

  /// Yeni program ([yerelId] null) ya da düzenleme. [hatirlatici] verilmezse mevcut hatırlatıcılar korunur (sunucu başlangıca göre kaydırır).
  Future<int> kaydet(
    Map<String, Object?> alanlar, {
    int? yerelId,
    HatirlaticiAyar? hatirlatici,
  }) async {
    final temiz = _hazirla({for (final a in programAlanlari) a: alanlar[a]});
    final govde = jsonEncode({
      ...temiz,
      if (hatirlatici != null) '_hat': hatirlatici.toJson(),
    });
    final hatJson = hatirlatici == null
        ? null
        : jsonEncode(hatirlatici.toJson());
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      if (yerelId == null) {
        id = await txn.insert('programlar', {
          ...temiz,
          'surum': 0,
          'hat_json': hatJson,
          'bekleyen': 1,
          'silindi': 0,
          'ara': _ara(temiz),
        });
        await txn.insert('p_kuyruk', {
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
        'programlar',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      await txn.update(
        'programlar',
        {...temiz, 'hat_json': ?hatJson, 'bekleyen': 1, 'ara': _ara(temiz)},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'p_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        // Aynı program için bekleyen işlem varsa birleştir; hatırlatıcı verilmediyse öncekini koru
        var yeniGovde = govde;
        if (hatirlatici == null) {
          final eski = jsonDecode(op.first['govde'] as String) as Map;
          if (eski['_hat'] != null) {
            yeniGovde = jsonEncode({...temiz, '_hat': eski['_hat']});
          }
        }
        await txn.update(
          'p_kuyruk',
          {'govde': yeniGovde, 'durum': 'bekliyor', 'mesaj': ''},
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('p_kuyruk', {
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

  /// Takvimde sürükle-bırak / yeniden boyutlandırma: yalnızca zamanı değiştirir.
  Future<void> tasi(int yerelId, DateTime bas, DateTime bit) async {
    final p = await getir(yerelId);
    if (p == null) return;
    await kaydet({
      'adi': p.adi,
      'tarih1': programZamanYaz(bas),
      'tarih2': programZamanYaz(bit),
      'yer': p.yer,
      'notlar': p.notlar,
      'renk': p.renkHex,
    }, yerelId: yerelId);
  }

  /// Programı siler. Henüz sunucuya gitmemişse yalnızca yerelden kalkar; aksi halde silme kuyruğa yazılır.
  Future<void> sil(int yerelId) async {
    final silinecekDosyalar = <String>[];
    await _db.transaction((txn) async {
      final r = await txn.query(
        'programlar',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'p_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      for (final d in await txn.query(
        'p_kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      )) {
        final yol = (jsonDecode(d['govde'] as String) as Map)['yol'];
        if (yol is String) silinecekDosyalar.add(yol);
      }
      await txn.delete(
        'p_kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(
          'programlar',
          where: 'yerel_id = ?',
          whereArgs: [yerelId],
        );
        return;
      }
      await txn.update(
        'programlar',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'p_kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('p_kuyruk', {
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
    await _db.insert('p_kuyruk', {
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
      'p_kuyruk',
      where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
      whereArgs: [yerelId],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<void> dosyaIsleminiIptalEt(KuyrukOp op) async {
    await _db.delete('p_kuyruk', where: 'id = ?', whereArgs: [op.id]);
    final yol = op.govde['yol'];
    if (op.tur == 'dosya' && yol is String) {
      try {
        await File(yol).delete();
      } catch (_) {}
    }
    _bildir();
  }

  Future<void> sunucuDosyasiniSil(int yerelId, int no, String ad) async {
    await _db.insert('p_kuyruk', {
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
    await _db.insert('program_ek', {
      'no': no,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(int no) async {
    final r = await _db.query('program_ek', where: 'no = ?', whereArgs: [no]);
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'p_kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM p_kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('p_kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuProgram,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('p_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'programlar',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuProgram != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM p_kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(Program.apiden(sunucuProgram));
        await txn.update(
          'programlar',
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
      'p_kuyruk',
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
      await txn.delete('p_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(Program.apiden(sunucu));
        await txn.update(
          'programlar',
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
      'p_kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('p_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          'programlar',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [
            ...programAlanlari,
            'surum',
            'ara',
            'hat_json',
            'randevu_no',
          ]) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'programlar',
          geri,
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  // ------------------------------------------------------------------ sunucudan gelenler

  /// Sunucudan gelen programları yerele işler. Yerelde gönderilmemiş değişikliği olanlar EZİLMEZ.
  Future<void> sunucudanYaz(
    List<Map<String, dynamic>> programlar,
    List<int> silinenler,
  ) async {
    if (programlar.isEmpty && silinenler.isEmpty) return;
    await _db.transaction((txn) async {
      for (final p in programlar) {
        final no = (p['no'] as num).toInt();
        final s = _hazirla(Program.apiden(p));
        final satir = {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0};
        final guncellenen = await txn.update(
          'programlar',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'programlar',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'programlar',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'programlar',
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
        'programlar',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans (hatırlatıcı seçenekleri, alıcılar) ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('p_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('p_referans');
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
