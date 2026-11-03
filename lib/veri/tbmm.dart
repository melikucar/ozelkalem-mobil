import 'yazi_formatlari.dart';

/// Sunucuya gönderilen alanlar. `icerik` düz metindir; yalnızca kullanıcı değiştirdiyse gönderilir.
const List<String> tbmmAlanlari = ['tablo', 'adi', 'tarih', 'icerik', 'notlar'];

class Tbmm {
  Tbmm(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;

  String s(String k) => (v[k] ?? '').toString();

  int get tablo => (v['tablo'] as int?) ?? 0;
  int get ekleyen => (v['ekleyen'] as int?) ?? 0;
  int get ek => (v['ek'] as int?) ?? 0;
  String get adi => s('adi');
  String get adBuyuk => trBuyuk(adi);
  String get icerik => s('icerik');
  String get icerikDuz => htmlDuz(icerik);
  String get notlar => s('notlar');

  DateTime get tarih => DateTime.tryParse(s('tarih')) ?? DateTime.now();

  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'tablo': (j['tablo'] as num?)?.toInt() ?? 0,
    'adi': (j['adi'] ?? '').toString(),
    'tarih': (j['tarih'] ?? '').toString().split(' ').first,
    'icerik': (j['icerik'] ?? '').toString(),
    'notlar': (j['notlar'] ?? '').toString(),
    'ekleyen': (j['ekleyen'] as num?)?.toInt() ?? 0,
    'ek': (j['ek'] as num?)?.toInt() ?? 0,
  };
}

String tbmmTarihYaz(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Liste süzgeci: seçili tür (0 = hepsi) ve arama sözcüğü.
class TbmmFiltre {
  const TbmmFiltre({this.tablo = 0, this.kelime = ''});

  final int tablo;
  final String kelime;

  TbmmFiltre kopya({int? tablo, String? kelime}) =>
      TbmmFiltre(tablo: tablo ?? this.tablo, kelime: kelime ?? this.kelime);
}

/// Sunucudan gelen referans: önerge türleri ve kaydedenler.
class TbmmReferans {
  TbmmReferans(this.v);

  final Map<String, dynamic> v;

  bool get bos => v.isEmpty;

  List<Map<String, dynamic>> _liste(String k) => [
    for (final x in (v[k] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  List<Map<String, dynamic>> get tablolar => _liste('tablolar');
  List<Map<String, dynamic>> get kaydedenler => _liste('kaydedenler');

  String tabloAdi(int no) {
    for (final t in tablolar) {
      if (t['no'] == no) return '${t['adi']}';
    }
    return '';
  }

  String kaydedenAdi(int no) {
    for (final k in kaydedenler) {
      if (k['no'] == no) return '${k['adi']}';
    }
    return '';
  }
}
