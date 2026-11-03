import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../api/api_istemci.dart';
import 'yazi_formatlari.dart';
import 'yerel_db.dart';

class Bakanlik {
  Bakanlik(this.no, this.adi);

  final int no;
  final String adi;
}

class Kurum {
  Kurum(this.v);

  final Map<String, dynamic> v;

  int get no => (v['no'] as num).toInt();
  int get katno => (v['katno'] as num).toInt();
  String s(String k) => (v[k] ?? '').toString().trim();
  String get adi => s('adi');
  String get unvan => s('unvan');
  String get telefon => s('telefon');
  String get dahili => s('dahili');
  String get telefon2 => s('telefon2');
  String get dahili2 => s('dahili2');
  String get faks => s('faks');
  String get eposta => s('eposta');

  /// Kartta görünen ana ad: ünvan (yoksa ad).
  String get baslik => unvan.isNotEmpty ? unvan : adi;

  /// Ünvan varsa kişinin adı.
  String get altBaslik => unvan.isNotEmpty && adi.isNotEmpty ? adi : '';

  /// Kurum grubu (web ile aynı hiyerarşi): "sıra|başlık".
  String get grup {
    var u = unvan.isNotEmpty ? unvan : adi;
    u = u.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    if (RegExp(r'(^|\s)Bakanı$').hasMatch(u)) return '0|Bakan';
    if (RegExp(r'Bakan Yardımcısı$').hasMatch(u)) return '1|Bakan Yardımcıları';
    if (RegExp(r'Genel Müdür(lüğü|ü)?$').hasMatch(u)) {
      return '2|Genel Müdürlükler';
    }
    if (RegExp(r'Genel Sekreter(liği|i)?$').hasMatch(u)) {
      return '3|Genel Sekreterlik';
    }
    if (RegExp(r'Başkan(lığı|ı)$').hasMatch(u)) return '4|Başkanlıklar';
    if (RegExp(r'Müdür(lüğü|ü)$').hasMatch(u)) return '5|Müdürlükler';
    if (RegExp(r'Müşavir(liği|i)$').hasMatch(u)) return '6|Müşavirlikler';
    if (RegExp(r'(Komutan|Rektör|Koordinatör|Temsilci)').hasMatch(u)) {
      return '7|Komutanlık, Rektörlük ve Diğer Birimler';
    }
    return '8|Diğer';
  }

  String get grupAdi => grup.split('|').last;

  String get ara => aramaMetni('$adi $unvan $telefon $eposta');
}

/// Öneri durumu → (etiket).
String oneriDurumAdi(String d) => switch (d) {
  'bekliyor' => 'Bekliyor',
  'onaylandi' => 'Onaylandı',
  'reddedildi' => 'Reddedildi',
  'iptal' => 'İptal edildi',
  _ => d,
};

String oneriTipAdi(String t) => switch (t) {
  'degistir' => 'Değişiklik',
  'ekle' => 'Yeni kurum',
  'kaldir' => 'Kaldırma',
  _ => t,
};

/// Bakanlık teşkilatları: ortak (makamsız) liste sunucudan çekilip cihazda saklanır (çevrimdışı okunur); öneriler çevrimiçi gönderilir.
class BakanlikServisi {
  BakanlikServisi(this._api, this._yerel);

  final ApiIstemci _api;
  final YerelDb _yerel;

  static const _anahtar = 'bk_liste';

  List<Bakanlik> bakanliklar = [];
  List<Kurum> kurumlar = [];

  /// {kurum no: {no, tip}} — bu makamın bekleyen önerileri.
  Map<int, Map<String, dynamic>> bekleyen = {};

  void _coz(Map<String, dynamic> v) {
    bakanliklar = [
      for (final x in (v['bakanliklar'] as List? ?? const []))
        Bakanlik((x['no'] as num).toInt(), '${x['adi']}'),
    ];
    kurumlar = [
      for (final x in (v['kurumlar'] as List? ?? const []))
        Kurum(Map<String, dynamic>.from(x as Map)),
    ];
    _bekleyenGuncelle(v);
  }

  /// Cihazdaki son liste (varsa). Dönen: veri var mı.
  Future<bool> onbellektenYukle() async {
    final r = await _yerel.db.query(
      'meta',
      where: 'anahtar = ?',
      whereArgs: [_anahtar],
    );
    if (r.isEmpty) return false;
    try {
      _coz(jsonDecode(r.first['deger'] as String) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sunucudan yeniler ve cihaza yazar. Ağ yoksa [ApiHata] fırlatır (eski liste korunur).
  Future<void> yenile() async {
    final v = await _api.get('bakanliklar/liste');
    _coz(v);
    await _yerel.db.insert('meta', {
      'anahtar': _anahtar,
      'deger': jsonEncode(v),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> oneriler({String durum = ''}) async {
    final v = await _api.get(
      'bakanliklar/oneriler${durum.isEmpty ? '' : '?durum=$durum'}',
    );
    return [
      for (final x in (v['oneriler'] as List))
        Map<String, dynamic>.from(x as Map),
    ];
  }

  Future<String> oner(Map<String, dynamic> govde) async {
    final v = await _api.post('bakanliklar/oner', govde: govde);
    _bekleyenGuncelle(v);
    return '${v['mesaj']}';
  }

  Future<String> iptal(int oneriNo) async {
    final v = await _api.post('bakanliklar/iptal', govde: {'id': oneriNo});
    _bekleyenGuncelle(v);
    return '${v['mesaj']}';
  }

  /// PHP boş diziyi `[]` olarak gönderir; nesne beklenen yerde liste gelirse boş sayılır.
  void _bekleyenGuncelle(Map<String, dynamic> v) {
    final b = v['bekleyen'];
    bekleyen = {
      if (b is Map)
        for (final e in b.entries)
          int.parse('${e.key}'): Map<String, dynamic>.from(e.value as Map),
    };
  }
}
