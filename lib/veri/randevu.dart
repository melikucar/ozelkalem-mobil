import 'program.dart' show programZamani, programZamanYaz, gunBasi;

/// Sunucuya gönderilen randevu alanları (yerel sütun adlarıyla aynı).
const List<String> randevuAlanlari = [
  'katno',
  'durum',
  'adi',
  'unvan',
  'telefon',
  'tarih',
  'sure_dk',
  'yer',
  'notlar',
];

/// Randevunun yerel satırı. Tarih "yyyy-MM-dd HH:mm:ss" (cihaz/sunucu yerel saati) olarak tutulur.
class Randevu {
  Randevu(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;

  String s(String k) => (v[k] ?? '').toString();

  int get katno => (v['katno'] as int?) ?? 1;
  int get durum => (v['durum'] as int?) ?? 1;
  String get adi => s('adi');
  String get unvan => s('unvan');
  String get telefon => s('telefon');
  String get yer => s('yer');
  String get notlar => s('notlar');
  int get sureDk => (v['sure_dk'] as int?) ?? 30;
  int get ekleyen => (v['ekleyen'] as int?) ?? 0;
  int get programNo => (v['program_no'] as int?) ?? 0;

  DateTime get bas => programZamani(v['tarih']) ?? DateTime.now();
  DateTime get bit => bas.add(Duration(minutes: sureDk));

  /// Sunucu yanıtındaki randevu → yerel sütunlar.
  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'katno': (j['katno'] as num?)?.toInt() ?? 1,
    'durum': (j['durum'] as num?)?.toInt() ?? 1,
    'adi': (j['adi'] ?? '').toString(),
    'unvan': (j['unvan'] ?? '').toString(),
    'telefon': (j['telefon'] ?? '').toString(),
    'tarih': (j['tarih'] ?? '').toString(),
    'sure_dk': (j['sure_dk'] as num?)?.toInt() ?? 30,
    'yer': (j['yer'] ?? '').toString(),
    'notlar': (j['notlar'] ?? '').toString(),
    'ekleyen': (j['ekleyen'] as num?)?.toInt() ?? 0,
    'program_no': (j['program_no'] as num?)?.toInt() ?? 0,
  };
}

String randevuZamanYaz(DateTime d) => programZamanYaz(d);

/// "Bugün", "Yarın", "3 gün sonra", "Geçti" … (7 günden uzak ya da dünden eski için boş / "Geçti").
({String etiket, int ton}) randevuGoreli(DateTime t, [DateTime? simdi]) {
  final fark = gunBasi(t).difference(gunBasi(simdi ?? DateTime.now())).inDays;
  if (fark == 0) return (etiket: 'Bugün', ton: 1);
  if (fark == 1) return (etiket: 'Yarın', ton: 2);
  if (fark > 1 && fark <= 7) return (etiket: '$fark gün sonra', ton: 0);
  if (fark < 0) return (etiket: 'Geçti', ton: 3);
  return (etiket: '', ton: 0);
}

/// Liste sekmesi.
enum RandevuZaman { yaklasan, bugun, gecmis, tumu }

/// Liste süzgeci. Boş değerler "hepsi" demektir.
class RandevuFiltre {
  const RandevuFiltre({
    this.zaman = RandevuZaman.yaklasan,
    this.katno = 0,
    this.durum = 0,
    this.kaydeden = 0,
    this.bas,
    this.bit,
    this.kelime = '',
  });

  final RandevuZaman zaman;
  final int katno;
  final int durum;
  final int kaydeden;
  final DateTime? bas;
  final DateTime? bit;
  final String kelime;

  /// Zaman sekmesi dışındaki süzgeçlerden kaç tanesi açık.
  int get etkin =>
      (katno != 0 ? 1 : 0) +
      (durum != 0 ? 1 : 0) +
      (kaydeden != 0 ? 1 : 0) +
      (bas != null || bit != null ? 1 : 0);

  RandevuFiltre kopya({
    RandevuZaman? zaman,
    int? katno,
    int? durum,
    int? kaydeden,
    DateTime? bas,
    DateTime? bit,
    bool tarihiTemizle = false,
    String? kelime,
  }) => RandevuFiltre(
    zaman: zaman ?? this.zaman,
    katno: katno ?? this.katno,
    durum: durum ?? this.durum,
    kaydeden: kaydeden ?? this.kaydeden,
    bas: tarihiTemizle ? null : (bas ?? this.bas),
    bit: tarihiTemizle ? null : (bit ?? this.bit),
    kelime: kelime ?? this.kelime,
  );
}
