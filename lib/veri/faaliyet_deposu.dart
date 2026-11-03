import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'faaliyet.dart';
import 'yazi_formatlari.dart';
import 'program.dart' show programZamanYaz, gunBasi;
import 'talep_deposu.dart' show KuyrukOp;
import 'yerel_db.dart';

/// Faaliyetler için yerel veri erişimi + giden kuyruk (programlar ile aynı mantık; tablolar `faaliyetler`, `f_kuyruk`, `faaliyet_ek`).
class FaaliyetDeposu extends ChangeNotifier {
  FaaliyetDeposu(this._yerel);

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
      aramaMetni('${m['adi'] ?? ''} ${htmlDuz('${m['icerik'] ?? ''}')}');

  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in ['adi', 'tarih', 'icerik', 'notlar', 'haberler']) {
      if (r.containsKey(k)) r[k] = (r[k] ?? '').toString();
    }
    for (final k in ['katno', 'yer', 'ekleyen']) {
      if (r.containsKey(k)) r[k] = (r[k] as num?)?.toInt() ?? 0;
    }
    return r;
  }

  // ------------------------------------------------------------------ okuma

  (String, List<Object?>) _kosul(FaaliyetFiltre f) {
    final k = <String>['silindi = 0'];
    final a = <Object?>[];
    if (f.katno != 0) {
      k.add('katno = ?');
      a.add(f.katno);
    }
    if (f.yer != 0) {
      k.add('yer = ?');
      a.add(f.yer);
    }
    if (f.kaydeden != 0) {
      k.add('ekleyen = ?');
      a.add(f.kaydeden);
    }
    if (f.bas != null) {
      k.add('tarih >= ?');
      a.add(programZamanYaz(gunBasi(f.bas!)));
    }
    if (f.bit != null) {
      k.add('tarih < ?');
      a.add(programZamanYaz(gunBasi(f.bit!).add(const Duration(days: 1))));
    }
    final kelime = aramaMetni(f.kelime);
    if (kelime.isNotEmpty) {
      k.add('ara LIKE ?');
      a.add('%$kelime%');
    }
    return (k.join(' AND '), a);
  }

  /// Süzgece uyan faaliyetler, en yeni üstte.
  Future<List<Faaliyet>> liste(
    FaaliyetFiltre f, {
    int limit = 60,
    int offset = 0,
  }) async {
    final (where, args) = _kosul(f);
    final r = await _db.query(
      'faaliyetler',
      where: where,
      whereArgs: args,
      orderBy: 'tarih DESC, yerel_id DESC',
      limit: limit,
      offset: offset,
    );
    return r.map(Faaliyet.new).toList();
  }

  Future<int> sonucSayisi(FaaliyetFiltre f) async {
    final (where, args) = _kosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM faaliyetler WHERE $where',
            args,
          ),
        ) ??
        0;
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery(
          'SELECT COUNT(*) FROM faaliyetler WHERE silindi = 0',
        ),
      ) ??
      0;

  Future<Faaliyet?> getir(int yerelId) async {
    final r = await _db.query(
      'faaliyetler',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Faaliyet(r.first);
  }

  /// Verilen sunucu numaralarının faaliyetleri, istenen sırayla (kitapçık sayfaları).
  Future<List<Faaliyet>> numaralarla(List<int> nolar) async {
    if (nolar.isEmpty) return [];
    final bulunan = <int, Faaliyet>{};
    for (var i = 0; i < nolar.length; i += 500) {
      final parca = nolar.skip(i).take(500).toList();
      final r = await _db.query(
        'faaliyetler',
        where:
            'silindi = 0 AND no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
      for (final x in r) {
        bulunan[x['no'] as int] = Faaliyet(x);
      }
    }
    return [
      for (final n in nolar)
        if (bulunan.containsKey(n)) bulunan[n]!,
    ];
  }

  Future<int?> yerelIdNo(int no) async {
    final r = await _db.query(
      'faaliyetler',
      columns: ['yerel_id'],
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['yerel_id'] as int?;
  }

  Future<int?> noBul(int yerelId) async {
    final r = await _db.query(
      'faaliyetler',
      columns: ['no'],
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
    );
    return r.isEmpty ? null : r.first['no'] as int?;
  }

  /// Küçük resim durumunu kaydeder (listede tekrar sorulmasın). Dinleyicileri uyarmaz.
  Future<void> resimDurumuYaz(int yerelId, int durum) => _db.update(
    'faaliyetler',
    {'resim': durum},
    where: 'yerel_id = ?',
    whereArgs: [yerelId],
  );

  // ------------------------------------------------------------------ yerel yazma (kuyruğa alır)

  /// Yeni faaliyet ([yerelId] null) ya da düzenleme. `icerik` / `notlar` yalnızca değiştiyse [alanlar]'a konur.
  Future<int> kaydet(Map<String, Object?> alanlar, {int? yerelId}) async {
    final gonderilecek = {
      for (final a in faaliyetAlanlari)
        if (alanlar.containsKey(a)) a: alanlar[a],
    };
    // yerelde paragraf HTML'i olarak da tutulur (sunucu yanıtı gelene dek)
    final yerel = Map<String, Object?>.from(gonderilecek);
    if (yerel.containsKey('icerik')) {
      yerel['icerik'] = duzdenHtml('${yerel['icerik'] ?? ''}');
    }
    if (yerel.containsKey('notlar')) {
      yerel['notlar'] = duzdenHtml('${yerel['notlar'] ?? ''}');
    }
    final temiz = _hazirla(yerel);
    final govde = jsonEncode(_hazirla(gonderilecek));
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      if (yerelId == null) {
        id = await txn.insert('faaliyetler', {
          ...temiz,
          'surum': 0,
          'bekleyen': 1,
          'silindi': 0,
          'ara': _ara(temiz),
        });
        await txn.insert('f_kuyruk', {
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
        'faaliyetler',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      final birlesik = {...mevcut, ...temiz};
      await txn.update(
        'faaliyetler',
        {...temiz, 'bekleyen': 1, 'ara': _ara(birlesik)},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'f_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        // bekleyen işleme birleştir: önceki düz metin alanları korunur
        final eski = jsonDecode(op.first['govde'] as String) as Map;
        await txn.update(
          'f_kuyruk',
          {
            'govde': jsonEncode({...eski, ..._hazirla(gonderilecek)}),
            'durum': 'bekliyor',
            'mesaj': '',
          },
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('f_kuyruk', {
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
        'faaliyetler',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'f_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      for (final d in await txn.query(
        'f_kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      )) {
        final yol = (jsonDecode(d['govde'] as String) as Map)['yol'];
        if (yol is String) silinecekDosyalar.add(yol);
      }
      await txn.delete(
        'f_kuyruk',
        where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(
          'faaliyetler',
          where: 'yerel_id = ?',
          whereArgs: [yerelId],
        );
        return;
      }
      await txn.update(
        'faaliyetler',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'f_kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('f_kuyruk', {
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
    await _db.insert('f_kuyruk', {
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
      'f_kuyruk',
      where: "yerel_id = ? AND tur IN ('dosya','dosya_sil')",
      whereArgs: [yerelId],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<void> dosyaIsleminiIptalEt(KuyrukOp op) async {
    await _db.delete('f_kuyruk', where: 'id = ?', whereArgs: [op.id]);
    final yol = op.govde['yol'];
    if (op.tur == 'dosya' && yol is String) {
      try {
        await File(yol).delete();
      } catch (_) {}
    }
    _bildir();
  }

  Future<void> sunucuDosyasiniSil(int yerelId, int no, String ad) async {
    await _db.insert('f_kuyruk', {
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
    await _db.insert('faaliyet_ek', {
      'no': no,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(int no) async {
    final r = await _db.query('faaliyet_ek', where: 'no = ?', whereArgs: [no]);
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'f_kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM f_kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('f_kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuFaaliyet,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('f_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'faaliyetler',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuFaaliyet != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM f_kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(Faaliyet.apiden(sunucuFaaliyet));
        await txn.update(
          'faaliyetler',
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
      'f_kuyruk',
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
      await txn.delete('f_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(Faaliyet.apiden(sunucu));
        await txn.update(
          'faaliyetler',
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
      'f_kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('f_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          'faaliyetler',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [...faaliyetAlanlari, 'surum', 'ara']) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'faaliyetler',
          geri,
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  // ------------------------------------------------------------------ sunucudan gelenler

  /// Yerelde gönderilmemiş değişikliği olanlar EZİLMEZ. Resim durumu korunur.
  Future<void> sunucudanYaz(
    List<Map<String, dynamic>> faaliyetler,
    List<int> silinenler,
  ) async {
    if (faaliyetler.isEmpty && silinenler.isEmpty) return;
    await _db.transaction((txn) async {
      for (final p in faaliyetler) {
        final no = (p['no'] as num).toInt();
        final s = _hazirla(Faaliyet.apiden(p));
        final satir = {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0};
        final guncellenen = await txn.update(
          'faaliyetler',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'faaliyetler',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'faaliyetler',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'faaliyetler',
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
        'faaliyetler',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans, kitapçıklar ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('f_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('f_referans');
    return s == null ? {} : jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> kitapciklarYaz(List<dynamic> liste) async {
    await metaYaz('f_kitapciklar', jsonEncode(liste));
    _bildir();
  }

  Future<List<Kitapcik>> kitapciklar() async {
    final s = await meta('f_kitapciklar');
    if (s == null) return [];
    return [
      for (final x in jsonDecode(s) as List)
        Kitapcik(Map<String, dynamic>.from(x as Map)),
    ];
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
