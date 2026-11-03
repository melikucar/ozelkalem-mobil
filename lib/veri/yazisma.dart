import 'program.dart' show programZamani;
import 'yazi_formatlari.dart';

/// Sunucuya gönderilen yazışma alanları (`icerik` ayrıca, yalnızca kullanıcı metni değiştirdiyse düz metin olarak gider).
const List<String> yazismaAlanlari = [
  'talep_eden',
  'kisi',
  'unvan',
  'logo',
  'imza',
  'imza_unvan',
  'imza_unvan_2',
  'alt_yazi',
];

/// Web ile aynı: yazışma bir talebe bağlıysa `talep_eden` talep numarasıdır; değilse serbest metin ("kayıtsız kişi").
bool talepNumarasi(String s) => RegExp(r'^[1-9]\d*$').hasMatch(s.trim());

class Yazisma {
  Yazisma(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;

  String s(String k) => (v[k] ?? '').toString();

  String get talepEden => s('talep_eden');
  String get talepAdi => s('talep_adi');
  bool get talepBagli => talepNumarasi(talepEden);

  /// Listede / ayrıntıda gösterilen "ilgili kişi": bağlı talepteki ad, yoksa serbest yazılan ad.
  String get ilgili {
    if (talepBagli) return talepAdi.trim();
    return talepEden.trim();
  }

  String get kisi => s('kisi');
  String get kisiBuyuk => trBuyuk(kisi);
  String get unvan => s('unvan');
  String get icerik => s('icerik');
  String get icerikDuz => htmlDuz(icerik).replaceAll(RegExp('[￼�​-‏  ﻿]'), '');

  bool get logo => (v['logo'] as int?) != 0;
  bool get imza => (v['imza'] as int?) != 0;
  bool get imzaUnvan => (v['imza_unvan'] as int?) != 0;
  bool get imzaUnvan2 => (v['imza_unvan_2'] as int?) != 0;
  bool get altYazi => (v['alt_yazi'] as int?) != 0;
  int get ekleyen => (v['ekleyen'] as int?) ?? 0;

  DateTime get tarih => programZamani(v['tarih']) ?? DateTime.now();

  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'talep_eden': (j['talep_eden'] ?? '').toString(),
    'talep_adi': (j['talep_adi'] ?? '').toString(),
    'kisi': (j['kisi'] ?? '').toString(),
    'unvan': (j['unvan'] ?? '').toString(),
    'icerik': (j['icerik'] ?? '').toString(),
    'tarih': (j['tarih'] ?? '').toString(),
    'logo': (j['logo'] as num?)?.toInt() ?? 1,
    'imza': (j['imza'] as num?)?.toInt() ?? 1,
    'imza_unvan': (j['imza_unvan'] as num?)?.toInt() ?? 1,
    'imza_unvan_2': (j['imza_unvan_2'] as num?)?.toInt() ?? 1,
    'alt_yazi': (j['alt_yazi'] as num?)?.toInt() ?? 1,
    'ekleyen': (j['ekleyen'] as num?)?.toInt() ?? 0,
  };
}

/// Web'deki dönem düğmeleri.
enum YazismaDonem {
  tum('Tümü', null),
  ay('Son 1 ay', 30),
  ucAy('Son 3 ay', 90),
  yil('Son 1 yıl', 365);

  const YazismaDonem(this.etiket, this.gun);
  final String etiket;
  final int? gun;
}

/// Yazışma listesi süzgeci. Boş değerler "hepsi" demektir.
class YazismaFiltre {
  const YazismaFiltre({
    this.kelime = '',
    this.donem = YazismaDonem.tum,
    this.kaydeden = 0,
    this.kisi = '',
  });

  final String kelime;
  final YazismaDonem donem;
  final int kaydeden;
  final String kisi;

  int get etkin =>
      (donem != YazismaDonem.tum ? 1 : 0) +
      (kaydeden != 0 ? 1 : 0) +
      (kisi.isNotEmpty ? 1 : 0);

  YazismaFiltre kopya({
    String? kelime,
    YazismaDonem? donem,
    int? kaydeden,
    String? kisi,
  }) => YazismaFiltre(
    kelime: kelime ?? this.kelime,
    donem: donem ?? this.donem,
    kaydeden: kaydeden ?? this.kaydeden,
    kisi: kisi ?? this.kisi,
  );
}

/// Sunucudan gelen referans: şablonlar, kaydedenler, şablon alan etiketleri.
class YazismaSablon {
  YazismaSablon({required this.no, required this.adi, required this.icerik});

  final int no;
  final String adi;
  final String icerik;

  factory YazismaSablon.apiden(Map<String, dynamic> j) => YazismaSablon(
    no: (j['no'] as num).toInt(),
    adi: (j['adi'] ?? '').toString(),
    icerik: (j['icerik'] ?? '').toString(),
  );
}

class YazismaReferans {
  YazismaReferans(Map<String, dynamic> j)
    : sablonlar = [
        for (final x in (j['sablonlar'] as List? ?? const []))
          YazismaSablon.apiden(Map<String, dynamic>.from(x as Map)),
      ],
      kaydedenler = [
        for (final x in (j['kaydedenler'] as List? ?? const []))
          (
            no: ((x as Map)['no'] as num).toInt(),
            adi: (x['adi'] ?? '').toString(),
          ),
      ],
      alanlar = {
        for (final e in ((j['alanlar'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      eposta = j['eposta'] == true,
      whatsapp = j['whatsapp'] == true,
      bos = j.isEmpty;

  final List<YazismaSablon> sablonlar;
  final List<({int no, String adi})> kaydedenler;

  /// Şablon alan anahtarı → etiket (AD_SOYAD → "Ad Soyad").
  final Map<String, String> alanlar;
  final bool eposta;
  final bool whatsapp;
  final bool bos;

  String kaydedenAdi(int no) {
    for (final k in kaydedenler) {
      if (k.no == no) return k.adi;
    }
    return '';
  }
}
