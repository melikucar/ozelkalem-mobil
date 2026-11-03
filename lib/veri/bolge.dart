import 'dart:convert';

import 'package:flutter/material.dart';

import 'yazi_formatlari.dart';

/// Bölge künyesindeki tek bir bilgi alanı. [coklu]: çok satırlı metin, [sayisal]: sayı klavyesi, [telefon]: telefon klavyesi.
class BolgeAlani {
  const BolgeAlani(
    this.anahtar,
    this.etiket, {
    this.coklu = false,
    this.sayisal = false,
    this.telefon = false,
  });

  final String anahtar;
  final String etiket;
  final bool coklu;
  final bool sayisal;
  final bool telefon;
}

class BolgeBolumu {
  const BolgeBolumu(this.ad, this.ikon, this.renk, this.alanlar);

  final String ad;
  final IconData ikon;
  final Color renk;
  final List<BolgeAlani> alanlar;
}

/// Web "Bölge ekle" formundaki bölümler ve alanlar (aynı sırayla).
const List<BolgeBolumu> bolgeBolumleri = [
  BolgeBolumu('Muhtar bilgileri', Icons.badge_outlined, Color(0xFF1D6FB8), [
    BolgeAlani('muhtar_adi', 'Adı soyadı'),
    BolgeAlani('muhtar_telefon', 'Telefonu', telefon: true),
    BolgeAlani('muhtar_yas', 'Yaşı', sayisal: true),
    BolgeAlani('muhtar_meslek', 'Mesleği'),
    BolgeAlani('muhtar_donem', 'Dönem sayısı', sayisal: true),
  ]),
  BolgeBolumu('Nüfus ve hane', Icons.groups_2_outlined, Color(0xFF1F8A5B), [
    BolgeAlani('toplam_nufus', 'Toplam nüfus', sayisal: true),
    BolgeAlani('kutuk_nufus', 'Kütüğe kayıtlı nüfus', sayisal: true),
    BolgeAlani('hane_sayi', 'Hane sayısı', sayisal: true),
    BolgeAlani('hane_sayi_yaz', 'Yaz ayları dolu hane', sayisal: true),
    BolgeAlani('ortalama_yas', 'Ortalama yaş', sayisal: true),
  ]),
  BolgeBolumu(
    'Sosyal yardım',
    Icons.volunteer_activism_outlined,
    Color(0xFFE11D48),
    [
      BolgeAlani('yardim_hane', 'Yardım alan hane', sayisal: true),
      BolgeAlani('yardim_hane_oran', 'Oran'),
      BolgeAlani('yardim_kisi', 'Yardım alan kişi', sayisal: true),
      BolgeAlani('yardim_kisi_oran', 'Nüfusa oranı'),
      BolgeAlani('sehit_sayi', 'Şehit sayısı', sayisal: true),
      BolgeAlani('gazi_sayi', 'Gazi sayısı', sayisal: true),
      BolgeAlani('engelli_sayi', 'Engelli birey sayısı', sayisal: true),
      BolgeAlani('evde_bakim_sayi', 'Evde bakım sayısı', sayisal: true),
    ],
  ),
  BolgeBolumu('Tarım ve hayvancılık', Icons.grass_rounded, Color(0xFF65A30D), [
    BolgeAlani('tarim_arazisi', 'Tarım arazisi'),
    BolgeAlani('sulu_arazi', 'Sulu arazi büyüklüğü'),
    BolgeAlani('kuru_arazi', 'Kuru arazi büyüklüğü'),
    BolgeAlani('tarla_buyukluk', 'Tarla/bahçe büyüklüğü'),
    BolgeAlani('tarim_disi_arazi', 'Tarım dışı arazi'),
    BolgeAlani('sulama_durumu', 'Sulama durumu'),
    BolgeAlani('mevsimlik_isci', 'Mevsimlik tarım işçisi'),
    BolgeAlani('urun_detaylari', 'Ürün detayları', coklu: true),
    BolgeAlani('buyukbas_sayi', 'Büyükbaş hayvan', sayisal: true),
    BolgeAlani('kucukbas_sayi', 'Küçükbaş hayvan', sayisal: true),
    BolgeAlani('kanatli_sayi', 'Kanatlı hayvan', sayisal: true),
  ]),
  BolgeBolumu('Sanayi', Icons.factory_outlined, Color(0xFF7C3AED), [
    BolgeAlani('osb', 'OSB bölgesi var mı?'),
    BolgeAlani('osb_istihdam', 'OSB istihdam sayısı', sayisal: true),
    BolgeAlani('ihracat_urunler', 'İhracat yapılan ürünler', coklu: true),
    BolgeAlani('urun_miktari', 'Ürün miktarı'),
    BolgeAlani('yillik_urun_miktari', 'Yıllık ihracat'),
  ]),
  BolgeBolumu('Eğitim', Icons.school_outlined, Color(0xFFEA580C), [
    BolgeAlani('okul', 'Okul var mı?'),
    BolgeAlani('ogretmen_sayi', 'Öğretmen sayısı', sayisal: true),
    BolgeAlani('ogrenci_sayi', 'Öğrenci sayısı', sayisal: true),
    BolgeAlani('tasimali_ogrenci_sayi', 'Taşımalı öğrenci', sayisal: true),
  ]),
  BolgeBolumu('Sağlık', Icons.local_hospital_outlined, Color(0xFFDC2626), [
    BolgeAlani('saglik_ocagi', 'Sağlık ocağı var mı?'),
    BolgeAlani('uzaklik_112', "Varsa 112'ye uzaklığı"),
    BolgeAlani('doktor_sayi', 'Doktor sayısı', sayisal: true),
    BolgeAlani('hemsire_sayi', 'Hemşire sayısı', sayisal: true),
  ]),
  BolgeBolumu(
    'Turizm, kültür ve spor',
    Icons.museum_outlined,
    Color(0xFF0891B2),
    [
      BolgeAlani('turizm', 'Turizm', coklu: true),
      BolgeAlani('kultur', 'Kültür', coklu: true),
      BolgeAlani('spor', 'Spor', coklu: true),
    ],
  ),
  BolgeBolumu('Genel bilgiler', Icons.apartment_outlined, Color(0xFF475569), [
    BolgeAlani('koy_konagi', 'Köy konağı'),
    BolgeAlani('sosyal_tesis', 'Sosyal tesis'),
    BolgeAlani('cocuk_oyun_parki', 'Çocuk oyun parkı'),
    BolgeAlani('spor_tesisi', 'Spor tesisi'),
    BolgeAlani('cami_sayi', 'Cami sayısı', sayisal: true),
    BolgeAlani('cami_buyukluk', 'Toplam alanı'),
    BolgeAlani('cami_personel', 'Toplam cami personeli', sayisal: true),
    BolgeAlani('yol_durumu', 'Yol durumu'),
    BolgeAlani('icme_suyu', 'İçme suyu'),
    BolgeAlani('atik_su', 'Atık su'),
    BolgeAlani('suc_oranlari', 'Suç oranları'),
    BolgeAlani('icra_dosya_sayi', 'İcra dosya sayısı', sayisal: true),
  ]),
  BolgeBolumu(
    'Seçim sonuçları',
    Icons.how_to_vote_outlined,
    Color(0xFFB91C1C),
    [BolgeAlani('secim_sonuclari', 'Seçim sonuçları', coklu: true)],
  ),
];

/// Sunucuya gönderilen anahtarlar (adres + tüm bilgi alanları).
final List<String> bolgeBilgiAnahtarlari = [
  for (final b in bolgeBolumleri)
    for (final a in b.alanlar) a.anahtar,
];

const List<String> bolgeAdresAnahtarlari = ['ilce', 'semt', 'mahalle'];

class Bolge {
  Bolge(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  int get ekleyen => (v['ekleyen'] as int?) ?? 0;
  int get ilce => (v['ilce'] as int?) ?? 0;
  int get semt => (v['semt'] as int?) ?? 0;
  int get mahalle => (v['mahalle'] as int?) ?? 0;
  String get ilceAdi => (v['ilce_adi'] ?? '').toString();
  String get semtAdi => (v['semt_adi'] ?? '').toString();
  String get mahalleAdi => (v['mahalle_adi'] ?? '').toString();
  DateTime get tarih =>
      DateTime.tryParse((v['tarih'] ?? '').toString()) ?? DateTime.now();

  Map<String, String> get bilgi {
    final j = v['veri'];
    if (j is! String || j.isEmpty) return {};
    return (jsonDecode(j) as Map).map((k, d) => MapEntry('$k', '$d'));
  }

  String alan(String k) => (bilgi[k] ?? '').trim();

  String get muhtar => alan('muhtar_adi');
  String get muhtarTelefon => alan('muhtar_telefon');

  /// Liste başlığı: köy/mahalle, yoksa semt, yoksa ilçe.
  String get baslik {
    for (final s in [mahalleAdi, semtAdi, ilceAdi]) {
      if (s.trim().isNotEmpty) return s.trim();
    }
    return '(Adsız bölge)';
  }

  /// "İlçe · Semt" alt satırı.
  String get konum =>
      [ilceAdi, semtAdi].where((e) => e.trim().isNotEmpty).join(' · ');

  /// Bilgi alanlarının dolu olanlarının yüzdesi (web'deki "doluluk").
  double get doluluk {
    final b = bilgi;
    var dolu = 0;
    for (final k in bolgeBilgiAnahtarlari) {
      if ((b[k] ?? '').trim().isNotEmpty) dolu++;
    }
    return (dolu * 1000 / bolgeBilgiAnahtarlari.length).round() / 10;
  }

  static Map<String, Object?> apiden(Map<String, dynamic> j) {
    final bilgi = <String, String>{
      for (final k in bolgeBilgiAnahtarlari) k: (j[k] ?? '').toString().trim(),
    };
    return {
      'no': j['no'],
      'surum': j['surum'] ?? 0,
      'il': (j['il'] as num?)?.toInt() ?? 0,
      'ilce': (j['ilce'] as num?)?.toInt() ?? 0,
      'semt': (j['semt'] as num?)?.toInt() ?? 0,
      'mahalle': (j['mahalle'] as num?)?.toInt() ?? 0,
      'ilce_adi': (j['ilce_adi'] ?? '').toString(),
      'semt_adi': (j['semt_adi'] ?? '').toString(),
      'mahalle_adi': (j['mahalle_adi'] ?? '').toString(),
      'tarih': (j['tarih'] ?? '').toString(),
      'ekleyen': (j['ekleyen'] as num?)?.toInt() ?? 0,
      'veri': jsonEncode(bilgi),
    };
  }

  /// Aramada kullanılacak metin: adres adları + tüm dolu bilgi alanları.
  static String aramaMetniUret(Map<String, Object?> m) {
    final j = m['veri'];
    final b = j is String && j.isNotEmpty
        ? (jsonDecode(j) as Map).values.join(' ')
        : '';
    return aramaMetni(
      '${m['ilce_adi'] ?? ''} ${m['semt_adi'] ?? ''} ${m['mahalle_adi'] ?? ''} $b',
    );
  }
}

/// Liste süzgeci: ilçe (0 = hepsi) ve arama sözcüğü.
class BolgeFiltre {
  const BolgeFiltre({this.ilce = 0, this.kelime = ''});

  final int ilce;
  final String kelime;

  BolgeFiltre kopya({int? ilce, String? kelime}) =>
      BolgeFiltre(ilce: ilce ?? this.ilce, kelime: kelime ?? this.kelime);
}

/// Sunucudan gelen referans: varsayılan il ve kaydedenler.
class BolgeReferans {
  BolgeReferans(this.v);

  final Map<String, dynamic> v;

  bool get bos => v.isEmpty;
  int get varsayilanIl => (v['varsayilan_il'] as num?)?.toInt() ?? 0;

  String kaydedenAdi(int no) {
    for (final k in (v['kaydedenler'] as List? ?? const [])) {
      if ((k as Map)['no'] == no) return '${k['adi']}';
    }
    return '';
  }
}
