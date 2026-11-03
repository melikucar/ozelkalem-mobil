import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'yazi_formatlari.dart';
import 'program.dart' show programZamanYaz, gunBasi;
import 'rehber.dart';
import 'talep_deposu.dart' show KuyrukOp;
import 'yerel_db.dart';

/// Rehberin iki varlığı: kişiler (telefon rehberi) ve telefon görüşmeleri.
enum RehberVarlik { kisi, gorusme }

class _V {
  const _V(this.tablo, this.kuyruk, this.alanlar, this.apiden, this.turet);

  final String tablo;
  final String kuyruk;
  final List<String> alanlar;
  final Map<String, Object?> Function(Map<String, dynamic>) apiden;

  /// Alanlardan türetilen yerel sütunlar (arama metni, harf, sıralama anahtarı).
  final Map<String, Object?> Function(Map<String, Object?>) turet;
}

String _rakam(String s) => s.replaceAll(RegExp(r'\D'), '');

Map<String, Object?> _kisiTuret(Map<String, Object?> m) {
  final adi = '${m['adi'] ?? ''}';
  final tel = [
    for (final k in ['cep1', 'cep2', 'is1', 'is2', 'faks'])
      _rakam('${m[k] ?? ''}'),
  ].where((x) => x.isNotEmpty).join(' ');
  return {
    'harf': ilkHarf(adi),
    'sira': siraAnahtari(adi),
    'ara': aramaMetni(
      '$adi ${m['unvan'] ?? ''} ${m['email'] ?? ''} ${m['notu'] ?? ''} ${m['adres'] ?? ''} $tel',
    ),
  };
}

Map<String, Object?> _gorusmeTuret(Map<String, Object?> m) => {
  'ara': aramaMetni(
    '${m['adi'] ?? ''} ${m['unvan'] ?? ''} ${m['konu'] ?? ''} ${m['notum'] ?? ''} ${_rakam('${m['tel1'] ?? ''}')} ${_rakam('${m['tel2'] ?? ''}')}',
  ),
};

final _kisi = _V('kisiler', 'h_kuyruk', kisiAlanlari, Kisi.apiden, _kisiTuret);
final _gorusme = _V(
  'gorusmeler',
  'g_kuyruk',
  gorusmeAlanlari,
  Gorusme.apiden,
  _gorusmeTuret,
);

/// Rehber (kişiler + telefon görüşmeleri) için yerel veri erişimi ve giden kuyruk. Ekranlar yalnızca bunu okur.
class RehberDeposu extends ChangeNotifier {
  RehberDeposu(this._yerel);

  final YerelDb _yerel;
  Database get _db => _yerel.db;

  static const _uuid = Uuid();

  VoidCallback? yerelYazildi;

  void _bildir() => notifyListeners();

  DateTime _sonBildirim = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _bildirimZamani;

  /// Toplu yüklemede ekranlar saniyede en çok bir kez tazelenir.
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

  _V _v(RehberVarlik v) => v == RehberVarlik.kisi ? _kisi : _gorusme;

  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in r.keys.toList()) {
      final x = r[k];
      if (x is bool) {
        r[k] = x ? 1 : 0;
      } else if (x == null) {
        r[k] = k == 'katno' || k == 'd1' || k == 'd2' || k == 'kara' ? 0 : '';
      }
    }
    return r;
  }

  // ------------------------------------------------------------------ kişiler: okuma

  /// Liste sırası: önce rakamla başlayanlar, sonra A–Z, en sonda diğerleri (harf çubuğundaki sıra).
  static const kisiSirasi =
      "CASE harf WHEN '0-9' THEN 0 WHEN '#' THEN 2 ELSE 1 END, sira, yerel_id";

  /// Aynı ad + ünvan + cep telefonlu tekrar kayıtlar listede bir kez görünür (web ile aynı).
  static const _tekil =
      'yerel_id IN (SELECT MIN(yerel_id) FROM kisiler WHERE silindi = 0 GROUP BY adi, unvan, cep1)';

  (String, List<Object?>) _kisiKosul(KisiFiltre f, {bool harfDahil = true}) {
    final k = <String>['silindi = 0', _tekil];
    final a = <Object?>[];
    final kelime = aramaMetni(f.kelime);
    if (kelime.isNotEmpty) {
      final rakam = _rakam(f.kelime);
      if (rakam.length >= 3) {
        k.add('(ara LIKE ? OR ara LIKE ?)');
        a
          ..add('%$kelime%')
          ..add('%$rakam%');
      } else {
        k.add('ara LIKE ?');
        a.add('%$kelime%');
      }
    }
    if (harfDahil && f.harf.isNotEmpty && kelime.isEmpty) {
      k.add('harf = ?');
      a.add(f.harf);
    }
    if (f.katno != 0) {
      k.add('katno = ?');
      a.add(f.katno);
    }
    if (f.karaListe) k.add('kara = 1');
    return (k.join(' AND '), a);
  }

  Future<List<Kisi>> kisiListe(
    KisiFiltre f, {
    int limit = 80,
    int offset = 0,
  }) async {
    final (w, a) = _kisiKosul(f);
    final r = await _db.query(
      'kisiler',
      where: w,
      whereArgs: a,
      orderBy: kisiSirasi,
      limit: limit,
      offset: offset,
    );
    return r.map(Kisi.new).toList();
  }

  Future<int> kisiSonucSayisi(KisiFiltre f) async {
    final (w, a) = _kisiKosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM kisiler WHERE $w', a),
        ) ??
        0;
  }

  Future<int> kisiSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery(
          'SELECT COUNT(*) FROM kisiler WHERE silindi = 0 AND $_tekil',
        ),
      ) ??
      0;

  /// Harf çubuğu için: seçili süzgece göre (harf hariç) harf başına kişi sayısı.
  Future<Map<String, int>> harfSayilari(KisiFiltre f) async {
    final (w, a) = _kisiKosul(f, harfDahil: false);
    final r = await _db.rawQuery(
      'SELECT harf, COUNT(*) AS n FROM kisiler WHERE $w GROUP BY harf',
      a,
    );
    return {for (final x in r) x['harf'] as String: x['n'] as int};
  }

  Future<Map<int, int>> kategoriSayilari(KisiFiltre f) async {
    final (w, a) = _kisiKosul(f.kopya(katno: 0));
    final r = await _db.rawQuery(
      'SELECT katno, COUNT(*) AS n FROM kisiler WHERE $w GROUP BY katno',
      a,
    );
    return {for (final x in r) x['katno'] as int: x['n'] as int};
  }

  Future<int> karaSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery(
          'SELECT COUNT(*) FROM kisiler WHERE silindi = 0 AND kara = 1 AND $_tekil',
        ),
      ) ??
      0;

  Future<Kisi?> kisiGetir(int yerelId) async {
    final r = await _db.query(
      'kisiler',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Kisi(r.first);
  }

  Future<int?> kisiYerelIdNo(int no) async {
    final r = await _db.query(
      'kisiler',
      columns: ['yerel_id'],
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['yerel_id'] as int?;
  }

  /// Ad ve/veya telefona göre rehberde kayıtlı kişi (görüşme ekranından rehbere geçiş için).
  Future<Kisi?> kisiBul(String adi, String tel) async {
    final r = await _db.query(
      'kisiler',
      where: 'silindi = 0 AND adi = ?',
      whereArgs: [adi],
      orderBy: 'sira',
    );
    if (r.isEmpty) return null;
    final rk = _rakam(tel);
    for (final x in r) {
      final k = Kisi(x);
      if (rk.isNotEmpty && _rakam(k.cep1) == rk) return k;
    }
    return Kisi(r.first);
  }

  /// Yazarken öneriler (ad, ünvan ya da telefondan).
  Future<List<Kisi>> kisiAra(String q, {int limit = 8}) async {
    if (q.trim().length < 2) return [];
    final (w, a) = _kisiKosul(KisiFiltre(kelime: q));
    final r = await _db.query(
      'kisiler',
      where: w,
      whereArgs: a,
      orderBy: kisiSirasi,
      limit: limit,
    );
    return r.map(Kisi.new).toList();
  }

  /// Önümüzdeki [gun] gün içinde doğum günü olanlar (en yakın üstte).
  Future<List<(Kisi, int)>> yaklasanDogumGunleri({int gun = 7}) async {
    final r = await _db.query('kisiler', where: "silindi = 0 AND dogum != ''");
    final cikti = <(Kisi, int)>[];
    final goruldu = <String>{};
    for (final x in r) {
      final k = Kisi(x);
      final d = k.sonrakiDogumGunu();
      if (d == null || d.kalan > gun) continue;
      if (!goruldu.add('${k.adi}|${k.cep1}')) continue;
      cikti.add((k, d.kalan));
    }
    cikti.sort((a, b) => a.$2.compareTo(b.$2));
    return cikti;
  }

  /// Kişi ayrıntısındaki sayılar: görüşme, talep, randevu.
  Future<({int gorusme, int talep, int randevu})> kisiSayilari(Kisi k) async {
    Future<int> say(String sql, List<Object?> a) async {
      try {
        return Sqflite.firstIntValue(await _db.rawQuery(sql, a)) ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final tel = k.cep1.trim();
    return (
      gorusme: await say(
        "SELECT COUNT(*) FROM gorusmeler WHERE silindi = 0 AND (adi = ? OR (? != '' AND tel1 = ?))",
        [k.adi, tel, tel],
      ),
      talep: await say(
        'SELECT COUNT(*) FROM talepler WHERE silindi = 0 AND talep_eden = ?',
        [k.adi],
      ),
      randevu: await say(
        'SELECT COUNT(*) FROM randevular WHERE silindi = 0 AND adi = ?',
        [k.adi],
      ),
    );
  }

  Future<List<Gorusme>> kisiGorusmeleri(Kisi k, {int limit = 12}) async {
    final tel = k.cep1.trim();
    final r = await _db.query(
      'gorusmeler',
      where: "silindi = 0 AND (adi = ? OR (? != '' AND tel1 = ?))",
      whereArgs: [k.adi, tel, tel],
      orderBy: 't1 DESC',
      limit: limit,
    );
    return r.map(Gorusme.new).toList();
  }

  // ------------------------------------------------------------------ görüşmeler: okuma

  (String, List<Object?>) _gorusmeKosul(
    GorusmeFiltre f, {
    bool durumDahil = true,
  }) {
    final k = <String>['silindi = 0'];
    final a = <Object?>[];
    final kelime = aramaMetni(f.kelime);
    if (kelime.isNotEmpty) {
      final rakam = _rakam(f.kelime);
      if (rakam.length >= 3) {
        k.add('(ara LIKE ? OR ara LIKE ?)');
        a
          ..add('%$kelime%')
          ..add('%$rakam%');
      } else {
        k.add('ara LIKE ?');
        a.add('%$kelime%');
      }
    }
    if (durumDahil && f.durum != 0) {
      k.add('d1 = ?');
      a.add(f.durum);
    }
    if (f.kaydeden != 0) {
      k.add('ekleyen = ?');
      a.add(f.kaydeden);
    }
    final bugun = gunBasi(DateTime.now());
    DateTime? bas;
    DateTime? bit;
    switch (f.donem) {
      case GorusmeDonemi.tumu:
        break;
      case GorusmeDonemi.bugun:
        bas = bugun;
        bit = bugun;
      case GorusmeDonemi.son7:
        bas = bugun.subtract(const Duration(days: 6));
        bit = bugun;
      case GorusmeDonemi.son30:
        bas = bugun.subtract(const Duration(days: 29));
        bit = bugun;
      case GorusmeDonemi.ozel:
        bas = f.bas;
        bit = f.bit;
    }
    if (bas != null) {
      k.add('t1 >= ?');
      a.add(programZamanYaz(gunBasi(bas)));
    }
    if (bit != null) {
      k.add('t1 < ?');
      a.add(programZamanYaz(gunBasi(bit).add(const Duration(days: 1))));
    }
    return (k.join(' AND '), a);
  }

  Future<List<Gorusme>> gorusmeListe(
    GorusmeFiltre f, {
    int limit = 60,
    int offset = 0,
  }) async {
    final (w, a) = _gorusmeKosul(f);
    final r = await _db.query(
      'gorusmeler',
      where: w,
      whereArgs: a,
      orderBy: 't1 DESC, yerel_id DESC',
      limit: limit,
      offset: offset,
    );
    return r.map(Gorusme.new).toList();
  }

  Future<int> gorusmeSonucSayisi(GorusmeFiltre f) async {
    final (w, a) = _gorusmeKosul(f);
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM gorusmeler WHERE $w', a),
        ) ??
        0;
  }

  Future<Map<int, int>> durumSayilari(GorusmeFiltre f) async {
    final (w, a) = _gorusmeKosul(f, durumDahil: false);
    final r = await _db.rawQuery(
      'SELECT d1, COUNT(*) AS n FROM gorusmeler WHERE $w GROUP BY d1',
      a,
    );
    return {for (final x in r) x['d1'] as int: x['n'] as int};
  }

  /// Üst özet: toplam, bugün, bu hafta, bu ay ve son 30 günde ulaşılamayıp takip edilmeyenler.
  Future<({int toplam, int bugun, int hafta, int ay, int ulasilamayan})>
  gorusmeOzeti() async {
    final bugun = gunBasi(DateTime.now());
    final haftaBasi = bugun.subtract(Duration(days: bugun.weekday - 1));
    final ayBasi = DateTime(bugun.year, bugun.month, 1);
    final otuz = bugun.subtract(const Duration(days: 30));
    String z(DateTime d) => programZamanYaz(d);
    final r = (await _db.rawQuery(
      'SELECT COUNT(*) AS t, '
      'COALESCE(SUM(t1 >= ?), 0) AS b, COALESCE(SUM(t1 >= ?), 0) AS h, COALESCE(SUM(t1 >= ?), 0) AS a, '
      'COALESCE(SUM(t1 >= ? AND d1 IN (2, 4) AND d2 = 0), 0) AS u '
      'FROM gorusmeler WHERE silindi = 0',
      [z(bugun), z(haftaBasi), z(ayBasi), z(otuz)],
    )).first;
    return (
      toplam: (r['t'] as int?) ?? 0,
      bugun: (r['b'] as int?) ?? 0,
      hafta: (r['h'] as int?) ?? 0,
      ay: (r['a'] as int?) ?? 0,
      ulasilamayan: (r['u'] as int?) ?? 0,
    );
  }

  Future<Gorusme?> gorusmeGetir(int yerelId) async {
    final r = await _db.query(
      'gorusmeler',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Gorusme(r.first);
  }

  Future<int?> gorusmeYerelIdNo(int no) async {
    final r = await _db.query(
      'gorusmeler',
      columns: ['yerel_id'],
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['yerel_id'] as int?;
  }

  Future<int> gorusmeSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM gorusmeler WHERE silindi = 0'),
      ) ??
      0;

  /// Aynı kişinin diğer görüşmeleri (ayrıntı ekranı).
  Future<List<Gorusme>> oncekiGorusmeler(Gorusme g, {int limit = 15}) async {
    final tel = g.tel1.trim();
    final r = await _db.query(
      'gorusmeler',
      where: "silindi = 0 AND yerel_id != ? AND (adi = ? OR (? != '' AND tel1 = ?))",
      whereArgs: [g.yerelId, g.adi, tel, tel],
      orderBy: 't1 DESC',
      limit: limit,
    );
    return r.map(Gorusme.new).toList();
  }

  // ------------------------------------------------------------------ yerel yazma (kuyruğa alır)

  Future<int> _kaydet(
    _V v,
    Map<String, Object?> alanlar, {
    int? yerelId,
    Map<String, Object?>? ekstra,
  }) async {
    final temiz = _hazirla({
      for (final a in v.alanlar)
        if (alanlar.containsKey(a)) a: alanlar[a],
    });
    final govdeMap = <String, Object?>{
      ...temiz,
      if (ekstra != null && ekstra.isNotEmpty) '_ek': ekstra,
    };
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      if (yerelId == null) {
        id = await txn.insert(v.tablo, {
          ...temiz,
          ...v.turet(temiz),
          'surum': 0,
          'bekleyen': 1,
          'silindi': 0,
        });
        await txn.insert(v.kuyruk, {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': id,
          'no': null,
          'taban': null,
          'govde': jsonEncode(govdeMap),
          'durum': 'bekliyor',
          'mesaj': '',
          'olusturma': simdi,
        });
        return;
      }
      id = yerelId;
      final mevcut = (await txn.query(
        v.tablo,
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      final birlesik = {...mevcut, ...temiz};
      await txn.update(
        v.tablo,
        {...temiz, ...v.turet(birlesik), 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        v.kuyruk,
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        final eski = jsonDecode(op.first['govde'] as String) as Map;
        await txn.update(
          v.kuyruk,
          {
            'govde': jsonEncode({...eski, ...govdeMap}),
            'durum': 'bekliyor',
            'mesaj': '',
          },
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert(v.kuyruk, {
          'istemci_id': _uuid.v4(),
          'tur': 'kaydet',
          'yerel_id': yerelId,
          'no': mevcut['no'],
          'taban': mevcut['surum'],
          'govde': jsonEncode(govdeMap),
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

  Future<void> _sil(_V v, int yerelId) async {
    await _db.transaction((txn) async {
      final r = await txn.query(
        v.tablo,
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        v.kuyruk,
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(v.tablo, where: 'yerel_id = ?', whereArgs: [yerelId]);
        return;
      }
      await txn.update(
        v.tablo,
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        v.kuyruk,
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert(v.kuyruk, {
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

  Future<int> kisiKaydet(Map<String, Object?> alanlar, {int? yerelId}) =>
      _kaydet(_kisi, alanlar, yerelId: yerelId);

  Future<void> kisiSil(int yerelId) => _sil(_kisi, yerelId);

  /// Kişiyi kara listeye alır / çıkarır (tüm alanlar korunur).
  Future<void> karaDegistir(int yerelId, bool kara) async {
    final k = await kisiGetir(yerelId);
    if (k == null) return;
    await kisiKaydet({
      for (final a in kisiAlanlari) a: k.v[a],
      'kara': kara,
    }, yerelId: yerelId);
  }

  /// [ekstra]: rehber_kayit, rehber_kategori, kara_liste.
  Future<int> gorusmeKaydet(
    Map<String, Object?> alanlar, {
    int? yerelId,
    Map<String, Object?>? ekstra,
  }) => _kaydet(_gorusme, alanlar, yerelId: yerelId, ekstra: ekstra);

  Future<void> gorusmeSil(int yerelId) => _sil(_gorusme, yerelId);

  // ------------------------------------------------------------------ ayrıntı önbelleği

  Future<void> ekYaz(String anahtar, Map<String, dynamic> ek) async {
    await _db.insert('rehber_ek', {
      'anahtar': anahtar,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(String anahtar) async {
    final r = await _db.query(
      'rehber_ek',
      where: 'anahtar = ?',
      whereArgs: [anahtar],
    );
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk(RehberVarlik v, {String? durum}) async {
    final r = await _db.query(
      _v(v).kuyruk,
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async {
    Future<int> n(String t) async =>
        Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $t')) ??
        0;
    return await n('h_kuyruk') + await n('g_kuyruk');
  }

  Future<Map<int, KuyrukOp>> sorunlular(RehberVarlik v) async {
    final r = await _db.query(_v(v).kuyruk, where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    RehberVarlik varlik,
    KuyrukOp op, {
    Map<String, dynamic>? sunucu,
  }) async {
    final v = _v(varlik);
    await _db.transaction((txn) async {
      await txn.delete(v.kuyruk, where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          v.tablo,
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucu != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM ${v.kuyruk} WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(v.apiden(sunucu));
        await txn.update(
          v.tablo,
          {...s, ...v.turet(s), 'bekleyen': kalan > 0 ? 1 : 0},
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  Future<void> islemSorunlu(
    RehberVarlik v,
    KuyrukOp op,
    String durum,
    String mesaj, {
    Map<String, dynamic>? sunucu,
  }) async {
    await _db.update(
      _v(v).kuyruk,
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

  Future<void> cakismaSunucuyuAl(RehberVarlik varlik, KuyrukOp op) async {
    final v = _v(varlik);
    final sunucu = op.sunucu;
    await _db.transaction((txn) async {
      await txn.delete(v.kuyruk, where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(v.apiden(sunucu));
        await txn.update(
          v.tablo,
          {...s, ...v.turet(s), 'bekleyen': 0, 'silindi': 0},
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      }
    });
    _bildir();
  }

  Future<void> cakismaBenimkiniGonder(RehberVarlik v, KuyrukOp op) async {
    final surum = (op.sunucu?['surum'] as num?)?.toInt() ?? op.taban;
    await _db.update(
      _v(v).kuyruk,
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(RehberVarlik varlik, KuyrukOp op) async {
    final v = _v(varlik);
    await _db.transaction((txn) async {
      await txn.delete(v.kuyruk, where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          v.tablo,
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [...v.alanlar, 'surum', 'ara', 'harf', 'sira']) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          v.tablo,
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
    RehberVarlik varlik,
    List<Map<String, dynamic>> kayitlar,
    List<int> silinenler,
  ) async {
    if (kayitlar.isEmpty && silinenler.isEmpty) return;
    final v = _v(varlik);
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final p in kayitlar) {
        final no = (p['no'] as num).toInt();
        final s = _hazirla(v.apiden(p));
        final satir = {...s, ...v.turet(s), 'bekleyen': 0, 'silindi': 0};
        // önce güncelle (gönderilmemiş yerel değişiklik yoksa), kayıt hiç yoksa ekle
        batch.update(
          v.tablo,
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        batch.insert(
          v.tablo,
          satir,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final no in silinenler) {
        batch.delete(
          v.tablo,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
      await batch.commit(noResult: true);
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(RehberVarlik varlik, Set<int> sunucuIdleri) async {
    final v = _v(varlik);
    final yerel = await _db.query(
      v.tablo,
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
        v.tablo,
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('h_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('h_referans');
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
