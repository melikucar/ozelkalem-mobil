import 'program.dart' show programZamani, gunBasi;

/// Sunucuya gönderilen kişi alanları (yerel sütun adlarıyla aynı).
const List<String> kisiAlanlari = [
  'katno',
  'adi',
  'unvan',
  'cep1',
  'cep2',
  'is1',
  'isd1',
  'is2',
  'isd2',
  'faks',
  'email',
  'adres',
  'notu',
  'dogum',
  'kara',
];

/// Sunucuya gönderilen görüşme alanları.
const List<String> gorusmeAlanlari = [
  'adi',
  'unvan',
  'tel1',
  'dah1',
  'tel2',
  'dah2',
  'konu',
  'd1',
  'd2',
  't1',
  't2',
  'notum',
];

class Kisi {
  Kisi(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;
  String s(String k) => (v[k] ?? '').toString();

  int get katno => (v['katno'] as int?) ?? 0;
  String get adi => s('adi');
  String get unvan => s('unvan');
  String get cep1 => s('cep1');
  String get cep2 => s('cep2');
  String get is1 => s('is1');
  String get isd1 => s('isd1');
  String get is2 => s('is2');
  String get isd2 => s('isd2');
  String get faks => s('faks');
  String get email => s('email');
  String get adres => s('adres');
  String get notu => s('notu');
  bool get kara => (v['kara'] as int?) == 1;
  String get harf => s('harf');

  /// Doğum günü (yıl dahil), yoksa null.
  DateTime? get dogum {
    final d = s('dogum');
    if (d.length < 10) return null;
    return DateTime.tryParse(d.substring(0, 10));
  }

  /// Aranabilecek ilk telefon (cep, sonra iş).
  String get anaTelefon => [
    cep1,
    cep2,
    is1,
    is2,
  ].firstWhere((x) => x.trim().isNotEmpty, orElse: () => '');

  bool get telefonVar => anaTelefon.isNotEmpty;

  /// Sonraki doğum günü ve kaç gün kaldığı (bugün = 0); doğum günü yoksa null.
  ({DateTime tarih, int kalan, int? yas})? sonrakiDogumGunu([DateTime? simdi]) {
    final d = dogum;
    if (d == null) return null;
    final bugun = gunBasi(simdi ?? DateTime.now());
    var t = DateTime(bugun.year, d.month, d.day);
    if (t.isBefore(bugun)) t = DateTime(bugun.year + 1, d.month, d.day);
    final yas = d.year > 1900 ? t.year - d.year : null;
    return (tarih: t, kalan: t.difference(bugun).inDays, yas: yas);
  }

  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'katno': (j['katno'] as num?)?.toInt() ?? 0,
    'adi': (j['adi'] ?? '').toString(),
    'unvan': (j['unvan'] ?? '').toString(),
    'cep1': (j['cep1'] ?? '').toString(),
    'cep2': (j['cep2'] ?? '').toString(),
    'is1': (j['is1'] ?? '').toString(),
    'isd1': (j['isd1'] ?? '').toString(),
    'is2': (j['is2'] ?? '').toString(),
    'isd2': (j['isd2'] ?? '').toString(),
    'faks': (j['faks'] ?? '').toString(),
    'email': (j['email'] ?? '').toString(),
    'adres': (j['adres'] ?? '').toString(),
    'notu': (j['notu'] ?? '').toString(),
    'dogum': (j['dogum'] ?? '').toString(),
    'kara': j['kara'] == true ? 1 : 0,
  };
}

class Gorusme {
  Gorusme(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;
  String s(String k) => (v[k] ?? '').toString();

  String get adi => s('adi');
  String get unvan => s('unvan');
  String get tel1 => s('tel1');
  String get dah1 => s('dah1');
  String get tel2 => s('tel2');
  String get dah2 => s('dah2');
  String get konu => s('konu');
  String get notum => s('notum');
  int get d1 => (v['d1'] as int?) ?? 0;
  int get d2 => (v['d2'] as int?) ?? 0;
  int get ekleyen => (v['ekleyen'] as int?) ?? 0;
  DateTime get t1 => programZamani(v['t1']) ?? DateTime.now();
  DateTime? get t2 => programZamani(v['t2']);

  /// Birinci görüşme "Görüşülemedi" mi ve takip görüşmesi yapılmamış mı? (durum 2 = Biz Aradık / Görüşülemedi, 4 = Onlar Aradı / Görüşülemedi)
  bool get ulasilamadi => (d1 == 2 || d1 == 4) && d2 == 0;

  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'adi': (j['adi'] ?? '').toString(),
    'unvan': (j['unvan'] ?? '').toString(),
    'tel1': (j['tel1'] ?? '').toString(),
    'dah1': (j['dah1'] ?? '').toString(),
    'tel2': (j['tel2'] ?? '').toString(),
    'dah2': (j['dah2'] ?? '').toString(),
    'konu': (j['konu'] ?? '').toString(),
    'd1': (j['d1'] as num?)?.toInt() ?? 0,
    'd2': (j['d2'] as num?)?.toInt() ?? 0,
    't1': (j['t1'] ?? '').toString(),
    't2': (j['t2'] ?? '').toString(),
    'notum': (j['notum'] ?? '').toString(),
    'ekleyen': (j['ekleyen'] as num?)?.toInt() ?? 0,
  };
}

/// Kişi listesi süzgeci. [harf]: '' (hepsi), 'A'…'Z', '0-9' ya da '#'.
class KisiFiltre {
  const KisiFiltre({
    this.kelime = '',
    this.harf = '',
    this.katno = 0,
    this.karaListe = false,
  });

  final String kelime;
  final String harf;
  final int katno;
  final bool karaListe;

  KisiFiltre kopya({
    String? kelime,
    String? harf,
    int? katno,
    bool? karaListe,
  }) => KisiFiltre(
    kelime: kelime ?? this.kelime,
    harf: harf ?? this.harf,
    katno: katno ?? this.katno,
    karaListe: karaListe ?? this.karaListe,
  );
}

enum GorusmeDonemi { tumu, bugun, son7, son30, ozel }

/// Görüşme listesi süzgeci.
class GorusmeFiltre {
  const GorusmeFiltre({
    this.kelime = '',
    this.durum = 0,
    this.kaydeden = 0,
    this.donem = GorusmeDonemi.tumu,
    this.bas,
    this.bit,
  });

  final String kelime;
  final int durum;
  final int kaydeden;
  final GorusmeDonemi donem;
  final DateTime? bas;
  final DateTime? bit;

  int get etkin =>
      (kaydeden != 0 ? 1 : 0) + (donem != GorusmeDonemi.tumu ? 1 : 0);

  GorusmeFiltre kopya({
    String? kelime,
    int? durum,
    int? kaydeden,
    GorusmeDonemi? donem,
    DateTime? bas,
    DateTime? bit,
  }) => GorusmeFiltre(
    kelime: kelime ?? this.kelime,
    durum: durum ?? this.durum,
    kaydeden: kaydeden ?? this.kaydeden,
    donem: donem ?? this.donem,
    bas: bas ?? this.bas,
    bit: bit ?? this.bit,
  );
}
