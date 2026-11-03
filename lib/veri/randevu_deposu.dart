import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'yazi_formatlari.dart';
import 'program.dart' show programZamanYaz, gunBasi;
import 'randevu.dart';
import 'talep_deposu.dart' show KuyrukOp;
import 'yerel_db.dart';

/// Randevular için yerel veri erişimi + giden kuyruk (programlar ile aynı mantık; tablolar `randevular`, `r_kuyruk`, `randevu_ek`).
class RandevuDeposu extends ChangeNotifier {
  RandevuDeposu(this._yerel);

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

  static String _ara(Map<String, Object?> m) => aramaMetni(
    '${m['adi'] ?? ''} ${m['unvan'] ?? ''} ${m['telefon'] ?? ''} ${m['yer'] ?? ''} ${m['notlar'] ?? ''}',
  );

  static Map<String, Object?> _hazirla(Map<String, Object?> m) {
    final r = Map<String, Object?>.from(m);
    for (final k in ['adi', 'unvan', 'telefon', 'tarih', 'yer', 'notlar']) {
      if (r.containsKey(k)) r[k] = (r[k] ?? '').toString();
    }
    for (final k in ['katno', 'durum', 'sure_dk', 'ekleyen', 'program_no']) {
      if (r.containsKey(k)) r[k] = (r[k] as num?)?.toInt() ?? 0;
    }
    return r;
  }

  // ------------------------------------------------------------------ okuma

  (String, List<Object?>) _kosul(RandevuFiltre f, {bool zamanDahil = true}) {
    final k = <String>['silindi = 0'];
    final a = <Object?>[];
    if (zamanDahil) {
      final bugun = gunBasi(DateTime.now());
      final yarin = bugun.add(const Duration(days: 1));
      switch (f.zaman) {
        case RandevuZaman.yaklasan:
          k.add('tarih >= ?');
          a.add(programZamanYaz(bugun));
        case RandevuZaman.bugun:
          k.add('tarih >= ? AND tarih < ?');
          a
            ..add(programZamanYaz(bugun))
            ..add(programZamanYaz(yarin));
        case RandevuZaman.gecmis:
          k.add('tarih < ?');
          a.add(programZamanYaz(bugun));
        case RandevuZaman.tumu:
          break;
      }
    }
    if (f.katno != 0) {
      k.add('katno = ?');
      a.add(f.katno);
    }
    if (f.durum != 0) {
      k.add('durum = ?');
      a.add(f.durum);
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

  /// Süzgece uyan randevular. Yaklaşan/bugün: en yakın üstte; geçmiş/tümü: en yeni üstte.
  Future<List<Randevu>> liste(RandevuFiltre f, {int limit = 400}) async {
    final (where, args) = _kosul(f);
    final artan =
        f.zaman == RandevuZaman.yaklasan || f.zaman == RandevuZaman.bugun;
    final r = await _db.query(
      'randevular',
      where: where,
      whereArgs: args,
      orderBy: artan ? 'tarih ASC, yerel_id' : 'tarih DESC, yerel_id DESC',
      limit: limit,
    );
    return r.map(Randevu.new).toList();
  }

  /// Zaman sekmelerinin sayaçları (diğer süzgeçlerden bağımsız, makamın tamamı).
  Future<Map<RandevuZaman, int>> zamanSayilari() async {
    final bugun = programZamanYaz(gunBasi(DateTime.now()));
    final yarin = programZamanYaz(
      gunBasi(DateTime.now()).add(const Duration(days: 1)),
    );
    final r = (await _db.rawQuery(
      'SELECT COUNT(*) AS tumu, '
      'COALESCE(SUM(tarih >= ?), 0) AS yaklasan, '
      'COALESCE(SUM(tarih >= ? AND tarih < ?), 0) AS bugun, '
      'COALESCE(SUM(tarih < ?), 0) AS gecmis '
      'FROM randevular WHERE silindi = 0',
      [bugun, bugun, yarin, bugun],
    )).first;
    return {
      RandevuZaman.tumu: (r['tumu'] as int?) ?? 0,
      RandevuZaman.yaklasan: (r['yaklasan'] as int?) ?? 0,
      RandevuZaman.bugun: (r['bugun'] as int?) ?? 0,
      RandevuZaman.gecmis: (r['gecmis'] as int?) ?? 0,
    };
  }

  /// Kategori çipleri için: seçili zaman sekmesi ve diğer süzgeçlerle (kategori hariç) kategori başına adet.
  Future<Map<int, int>> kategoriSayilari(RandevuFiltre f) async {
    final (where, args) = _kosul(f.kopya(katno: 0));
    final r = await _db.rawQuery(
      'SELECT katno, COUNT(*) AS n FROM randevular WHERE $where GROUP BY katno',
      args,
    );
    return {for (final s in r) s['katno'] as int: s['n'] as int};
  }

  Future<Randevu?> getir(int yerelId) async {
    final r = await _db.query(
      'randevular',
      where: 'yerel_id = ?',
      whereArgs: [yerelId],
      limit: 1,
    );
    return r.isEmpty ? null : Randevu(r.first);
  }

  Future<int?> yerelIdNo(int no) async {
    final r = await _db.query(
      'randevular',
      columns: ['yerel_id'],
      where: 'no = ? AND silindi = 0',
      whereArgs: [no],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['yerel_id'] as int?;
  }

  Future<int> sayi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM randevular WHERE silindi = 0'),
      ) ??
      0;

  /// Aynı kişi/telefon için daha önceki randevular (en yeni üstte) — ayrıntı ekranındaki "geçmiş".
  Future<List<Randevu>> kisiGecmisi(Randevu r, {int limit = 8}) async {
    final tel = r.telefon.replaceAll(RegExp(r'\D'), '');
    final r2 = await _db.query(
      'randevular',
      where:
          'silindi = 0 AND yerel_id != ? AND (adi = ?${tel.length >= 7 ? ' OR REPLACE(REPLACE(REPLACE(telefon, " ", ""), "(", ""), ")", "") LIKE ?' : ''})',
      whereArgs: [r.yerelId, r.adi, if (tel.length >= 7) '%$tel%'],
      orderBy: 'tarih DESC',
      limit: limit,
    );
    return r2.map(Randevu.new).toList();
  }

  // ------------------------------------------------------------------ yerel yazma (kuyruğa alır)

  /// Yeni randevu ([yerelId] null) ya da düzenleme. [hatirlatici]: dakika (-1: yok, null: sunucu varsayılanı/dokunma).
  /// [ekstra]: sms_randevu, rehber_kayit, rehber_kategori, kara_liste.
  Future<int> kaydet(
    Map<String, Object?> alanlar, {
    int? yerelId,
    int? hatirlatici,
    Map<String, Object?>? ekstra,
  }) async {
    final temiz = _hazirla({for (final a in randevuAlanlari) a: alanlar[a]});
    final govde = jsonEncode({
      ...temiz,
      '_hat': ?hatirlatici,
      if (ekstra != null && ekstra.isNotEmpty) '_ek': ekstra,
    });
    late int id;
    await _db.transaction((txn) async {
      final simdi = DateTime.now().millisecondsSinceEpoch;
      if (yerelId == null) {
        id = await txn.insert('randevular', {
          ...temiz,
          'surum': 0,
          'bekleyen': 1,
          'silindi': 0,
          'ara': _ara(temiz),
        });
        await txn.insert('r_kuyruk', {
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
        'randevular',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      )).first;
      await txn.update(
        'randevular',
        {...temiz, 'bekleyen': 1, 'ara': _ara(temiz)},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final op = await txn.query(
        'r_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet' AND durum != 'cakisma'",
        whereArgs: [yerelId],
        limit: 1,
      );
      if (op.isNotEmpty) {
        await txn.update(
          'r_kuyruk',
          {'govde': govde, 'durum': 'bekliyor', 'mesaj': ''},
          where: 'id = ?',
          whereArgs: [op.first['id']],
        );
      } else {
        await txn.insert('r_kuyruk', {
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

  /// Yalnızca durumu değiştirir (listeden hızlı işlem).
  Future<void> durumDegistir(int yerelId, int durum) async {
    final r = await getir(yerelId);
    if (r == null) return;
    await kaydet({
      'katno': r.katno,
      'durum': durum,
      'adi': r.adi,
      'unvan': r.unvan,
      'telefon': r.telefon,
      'tarih': r.s('tarih'),
      'sure_dk': r.sureDk,
      'yer': r.yer,
      'notlar': r.notlar,
    }, yerelId: yerelId);
  }

  Future<void> sil(int yerelId) async {
    await _db.transaction((txn) async {
      final r = await txn.query(
        'randevular',
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      if (r.isEmpty) return;
      await txn.delete(
        'r_kuyruk',
        where: "yerel_id = ? AND tur = 'kaydet'",
        whereArgs: [yerelId],
      );
      final no = r.first['no'] as int?;
      if (no == null) {
        await txn.delete(
          'randevular',
          where: 'yerel_id = ?',
          whereArgs: [yerelId],
        );
        return;
      }
      await txn.update(
        'randevular',
        {'silindi': 1, 'bekleyen': 1},
        where: 'yerel_id = ?',
        whereArgs: [yerelId],
      );
      final var_ = await txn.query(
        'r_kuyruk',
        where: "yerel_id = ? AND tur = 'sil'",
        whereArgs: [yerelId],
      );
      if (var_.isEmpty) {
        await txn.insert('r_kuyruk', {
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
    await _db.insert('randevu_ek', {
      'no': no,
      'json': jsonEncode(ek),
      'zaman': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bildir();
  }

  Future<Map<String, dynamic>?> ekOku(int no) async {
    final r = await _db.query('randevu_ek', where: 'no = ?', whereArgs: [no]);
    return r.isEmpty
        ? null
        : jsonDecode(r.first['json'] as String) as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------ kuyruk

  Future<List<KuyrukOp>> kuyruk({String? durum}) async {
    final r = await _db.query(
      'r_kuyruk',
      where: durum == null ? null : 'durum = ?',
      whereArgs: durum == null ? null : [durum],
      orderBy: 'id',
    );
    return r.map(KuyrukOp.new).toList();
  }

  Future<int> kuyrukSayisi() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM r_kuyruk'),
      ) ??
      0;

  Future<Map<int, KuyrukOp>> sorunlular() async {
    final r = await _db.query('r_kuyruk', where: "durum != 'bekliyor'");
    return {for (final s in r) s['yerel_id'] as int: KuyrukOp(s)};
  }

  Future<void> islemBasarili(
    KuyrukOp op, {
    Map<String, dynamic>? sunucuRandevu,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('r_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.tur == 'sil') {
        await txn.delete(
          'randevular',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
        return;
      }
      if (sunucuRandevu != null) {
        final kalan =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM r_kuyruk WHERE yerel_id = ?',
                [op.yerelId],
              ),
            ) ??
            0;
        final s = _hazirla(Randevu.apiden(sunucuRandevu));
        await txn.update(
          'randevular',
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
      'r_kuyruk',
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
      await txn.delete('r_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (sunucu != null) {
        final s = _hazirla(Randevu.apiden(sunucu));
        await txn.update(
          'randevular',
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
      'r_kuyruk',
      {'taban': surum, 'durum': 'bekliyor', 'mesaj': '', 'sunucu_json': null},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    _bildir();
  }

  Future<void> islemiIptalEt(KuyrukOp op) async {
    await _db.transaction((txn) async {
      await txn.delete('r_kuyruk', where: 'id = ?', whereArgs: [op.id]);
      if (op.no == null) {
        await txn.delete(
          'randevular',
          where: 'yerel_id = ?',
          whereArgs: [op.yerelId],
        );
      } else {
        final onceki = op.satir['onceki_json'] as String?;
        final geri = <String, Object?>{'bekleyen': 0, 'silindi': 0};
        if (onceki != null) {
          final m = jsonDecode(onceki) as Map<String, dynamic>;
          for (final k in [...randevuAlanlari, 'surum', 'ara', 'program_no']) {
            if (m.containsKey(k)) geri[k] = m[k];
          }
        }
        await txn.update(
          'randevular',
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
    List<Map<String, dynamic>> randevular,
    List<int> silinenler,
  ) async {
    if (randevular.isEmpty && silinenler.isEmpty) return;
    await _db.transaction((txn) async {
      for (final p in randevular) {
        final no = (p['no'] as num).toInt();
        final s = _hazirla(Randevu.apiden(p));
        final satir = {...s, 'ara': _ara(s), 'bekleyen': 0, 'silindi': 0};
        final guncellenen = await txn.update(
          'randevular',
          satir,
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
        if (guncellenen == 0) {
          await txn.insert(
            'randevular',
            satir,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      for (final no in silinenler) {
        await txn.delete(
          'randevular',
          where: 'no = ? AND bekleyen = 0',
          whereArgs: [no],
        );
      }
    });
    _seyrekBildir();
  }

  Future<int> uzlastir(Set<int> sunucuIdleri) async {
    final yerel = await _db.query(
      'randevular',
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
        'randevular',
        where: 'no IN (${List.filled(parca.length, '?').join(',')})',
        whereArgs: parca,
      );
    }
    if (fazla.isNotEmpty) _bildir();
    return fazla.length;
  }

  // ------------------------------------------------------------------ referans ve meta

  Future<void> referansYaz(Map<String, dynamic> v) async {
    await metaYaz('r_referans', jsonEncode(v));
    _bildir();
  }

  Future<Map<String, dynamic>> referans() async {
    final s = await meta('r_referans');
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
