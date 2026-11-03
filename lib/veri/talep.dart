import 'dart:convert';

import 'yazi_formatlari.dart';

/// Sunucuyla taşınan, kullanıcının düzenleyebildiği talep alanları.
const List<String> talepAlanlari = [
  'il',
  'ilce',
  'semt',
  'mahalle',
  'talep_eden',
  'tcno',
  'icerik',
  'telefon',
  'katno',
  'mulakat_tarihi',
  'mulakat_yeri',
  'referans',
  'referans_telefon',
  'tarih',
  'durum',
  'yapilan_islem',
  'ilgili_kurum',
  'hatirlatici',
  'hatirlatici_tarih',
];

/// Sunucudan gelen ama mobilde düzenlenmeyen alanlar.
const List<String> saltOkunur = ['sonuc', 'ekleyen'];

/// Yerel veritabanındaki bir talep satırı.
class Talep {
  Talep(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;

  String s(String k) => (v[k] ?? '').toString();
  int i(String k) => (v[k] as int?) ?? 0;

  String get talepEden => s('talep_eden');

  /// Ekranlarda gösterilen ad: Türkçe kurallarıyla tümü büyük harf.
  String get adBuyuk => trBuyuk(talepEden.trim());
  String get telefon => s('telefon');
  int get durum => i('durum');
  int get katno => i('katno');
  String? get tarih => v['tarih'] as String?;
  String? get mulakatTarihi => v['mulakat_tarihi'] as String?;

  /// API'ye gönderilecek alanlar (düzenlenebilir olanlar).
  Map<String, Object?> alanlar() => {for (final a in talepAlanlari) a: v[a]};

  /// Sunucu yanıtındaki (veya 409'daki `sunucu`) kaydı yerel sütunlarına çevirir.
  static Map<String, Object?> apiden(Map<String, dynamic> j) {
    final m = <String, Object?>{'no': j['no'], 'surum': j['surum'] ?? 0};
    for (final a in [...talepAlanlari, ...saltOkunur]) {
      m[a] = j[a];
    }
    return m;
  }

  static String json(Map<String, Object?> m) => jsonEncode(m);
}
