import 'yazi_formatlari.dart';
import 'program.dart' show programZamani, gunBasi, programZamanYaz;

/// Sunucuya gönderilen faaliyet alanları. `icerik` ve `notlar` düz metindir; yalnızca kullanıcı değiştirdiyse gönderilir.
const List<String> faaliyetAlanlari = [
  'adi',
  'katno',
  'yer',
  'tarih',
  'icerik',
  'notlar',
  'haberler',
];

/// Düz metni web editörünün sakladığı paragraf HTML'ine çevirir (sunucudaki ile aynı kural; yerel gösterim için).
String duzdenHtml(String metin) {
  final m = metin.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (m.isEmpty) return '';
  String kac(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');
  return [for (final s in m.split('\n')) '<p>${kac(s.trim())}</p>'].join();
}

class Faaliyet {
  Faaliyet(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;

  String s(String k) => (v[k] ?? '').toString();

  int get katno => (v['katno'] as int?) ?? 0;
  int get yer => (v['yer'] as int?) ?? 0;
  int get ekleyen => (v['ekleyen'] as int?) ?? 0;
  String get adi => s('adi');
  String get adBuyuk => trBuyuk(adi);
  String get icerik => s('icerik');
  String get notlar => s('notlar');
  String get icerikDuz => htmlDuz(icerik);
  String get notlarDuz => htmlDuz(notlar);

  /// Haberler alanı "a@b" biçiminde bağlantı listesidir.
  List<String> get haberler => [
    for (final x in s('haberler').split(RegExp(r'[@\s]+')))
      if (x.trim().isNotEmpty) x.trim(),
  ];

  DateTime get tarih => programZamani(v['tarih']) ?? DateTime.now();

  /// 0: henüz bakılmadı, 1: resmi var, 2: resmi yok
  int get resimDurumu => (v['resim'] as int?) ?? 0;

  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'katno': (j['katno'] as num?)?.toInt() ?? 0,
    'yer': (j['yer'] as num?)?.toInt() ?? 0,
    'adi': (j['adi'] ?? '').toString(),
    'tarih': (j['tarih'] ?? '').toString(),
    'icerik': (j['icerik'] ?? '').toString(),
    'notlar': (j['notlar'] ?? '').toString(),
    'haberler': (j['haberler'] ?? '').toString(),
    'ekleyen': (j['ekleyen'] as num?)?.toInt() ?? 0,
  };
}

String faaliyetZamanYaz(DateTime d) => programZamanYaz(d);

/// Liste süzgeci. Boş değerler "hepsi" demektir.
class FaaliyetFiltre {
  const FaaliyetFiltre({
    this.kelime = '',
    this.katno = 0,
    this.yer = 0,
    this.kaydeden = 0,
    this.bas,
    this.bit,
  });

  final String kelime;
  final int katno;
  final int yer;
  final int kaydeden;
  final DateTime? bas;
  final DateTime? bit;

  int get etkin =>
      (katno != 0 ? 1 : 0) +
      (yer != 0 ? 1 : 0) +
      (kaydeden != 0 ? 1 : 0) +
      (bas != null || bit != null ? 1 : 0);

  FaaliyetFiltre kopya({
    String? kelime,
    int? katno,
    int? yer,
    int? kaydeden,
    DateTime? bas,
    DateTime? bit,
    bool tarihiTemizle = false,
  }) => FaaliyetFiltre(
    kelime: kelime ?? this.kelime,
    katno: katno ?? this.katno,
    yer: yer ?? this.yer,
    kaydeden: kaydeden ?? this.kaydeden,
    bas: tarihiTemizle ? null : (bas ?? this.bas),
    bit: tarihiTemizle ? null : (bit ?? this.bit),
  );
}

/// Sunucudan gelen kitapçık (yalnızca okunur). Sayfa içerikleri yerel faaliyetlerden alınır.
class Kitapcik {
  Kitapcik(this.v);

  final Map<String, dynamic> v;

  int get no => (v['no'] as num).toInt();
  String get adi => '${v['adi'] ?? ''}'.trim();
  String get baslikTek => adi.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  List<String> get baslikSatirlari => [
    for (final s in adi.split('\n'))
      if (s.trim().isNotEmpty) s.trim(),
  ];
  String get unvan => '${v['unvan'] ?? ''}'.trim();
  String get sablon => '${v['sablon'] ?? ''}';
  String get yazi => '${v['yazi'] ?? '#11396b'}';
  String get cizgi => '${v['cizgi'] ?? '#1f6491'}';
  String get zemin => '${v['zemin'] ?? '#e1ecf4'}';
  DateTime get tarih => programZamani(v['tarih']) ?? DateTime.now();
  bool get taslak => v['taslak'] == true;
  bool get icindekiler => v['icindekiler'] != false;
  String get onsoz => '${v['onsoz'] ?? ''}'.trim();
  String get ekleyen => '${v['ekleyen'] ?? ''}';
  List<int> get faaliyetler => [
    for (final x in (v['faaliyetler'] as List? ?? const [])) (x as num).toInt(),
  ];
  List<String> get kapakFoto => [
    for (final x in (v['kapak_foto'] as List? ?? const [])) '$x',
  ];
}

/// "#rrggbb" → Color değeri (geçersizse [yedek]).
int renkDegeri(String hex, [int yedek = 0xFF11396B]) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  return m == null ? yedek : int.parse('FF${m.group(1)}', radix: 16);
}

DateTime faaliyetGunu(DateTime d) => gunBasi(d);
