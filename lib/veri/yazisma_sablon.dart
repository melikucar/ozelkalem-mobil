/// Üst yazı şablonları (web `yazisma-sablon.js` ile aynı kurallar):
///  - `{{AD_SOYAD}}` gibi alan etiketleri seçilen talepten doldurulur,
///  - eski şablonlardaki "........." boşlukları bağlama göre tahmin edilir (tahmin edilemeyenler elle doldurulur),
///  - hitap, yazının yöneltildiği makama göre düzeltilir ("Sayın Bakanım;", "Bakanlığınız" …).
class YazismaSablonMotoru {
  YazismaSablonMotoru._();

  static final _etiket = RegExp(r'\{\{([A-Z_]+)\}\}');
  static final _bosluk = RegExp(r'\{\{([A-Z_]+)\}\}|(\.{4,}|…{2,})');

  /// Boşluğun öncesi / sonrasındaki metinden hangi alan olduğunu tahmin eder ('' = emin değil).
  static String tahmin(String onceki, String sonraki) {
    if (RegExp(r'^\s*\(\s*T\.?\s?C', caseSensitive: false).hasMatch(sonraki)) {
      return 'AD_SOYAD';
    }
    if (RegExp(
      r'T\.?\s?C\.?\s*(KN|Kimlik)[^:]{0,14}:\s*$',
      caseSensitive: false,
    ).hasMatch(onceki)) {
      return 'TCKN';
    }
    if (RegExp(r'Sayın\s*$', caseSensitive: false).hasMatch(onceki)) {
      return 'AD_SOYAD';
    }
    if (RegExp(
      r'^\s*tarih(inde|li|ine)\b',
      caseSensitive: false,
    ).hasMatch(sonraki)) {
      return 'MULAKAT_TARIHI';
    }
    if (RegExp(
      r'Tel(efon)?\.?\s*:\s*$',
      caseSensitive: false,
    ).hasMatch(onceki)) {
      return 'TELEFON';
    }
    return '';
  }

  /// Şablonu kurar: hitap düzeltmesi + alanların doldurulması. [bos]: doldurulamayan boşluk sayısı.
  static ({String metin, int bos}) uygula(
    String ham,
    Map<String, String> veri, {
    String? hedef,
  }) {
    final h = hedef == null ? ham : hitapDonustur(ham, hedef);
    var bos = 0;
    final sb = StringBuffer();
    var son = 0;
    for (final m in _bosluk.allMatches(h)) {
      sb.write(h.substring(son, m.start));
      final etiket = m.group(1);
      final alan =
          etiket ??
          tahmin(
            h.substring(m.start < 40 ? 0 : m.start - 40, m.start),
            h.substring(m.end, m.end + 40 > h.length ? h.length : m.end + 40),
          );
      final deger = alan.isEmpty ? '' : (veri[alan] ?? '').trim();
      if (deger.isEmpty) {
        sb.write(m.group(0));
        bos++;
      } else {
        sb.write(deger);
      }
      son = m.end;
    }
    sb.write(h.substring(son));
    return (metin: sb.toString(), bos: bos);
  }

  /// Metinde kalan doldurulmamış boşluk / etiket sayısı (kaydetmeden önce uyarı için).
  static int kalanBosluk(String metin) => _bosluk.allMatches(metin).length;

  static bool etiketVar(String metin) => _etiket.hasMatch(metin);

  // ------------------------------------------------------------------ hitap

  // [selam, kök, iyelik eki, ünlü uyumu: 'a' (a/ı) | 'e' (e/i) | 'o' (a/u) | 'ö' (e/ü)]
  static const _hitap = <String, List<String?>>{
    'bakan': ['Bakanım', 'Bakanlığ', 'ınız', 'a'],
    'genelmd': ['Genel Müdürüm', 'Genel Müdürlüğ', 'ünüz', 'ö'],
    'mudur': ['Müdürüm', 'Müdürlüğ', 'ünüz', 'ö'],
    'baskan': ['Başkanım', 'Başkanlığ', 'ınız', 'a'],
    'musavir': ['Müşavirim', 'Müşavirliğ', 'iniz', 'e'],
    'komutan': ['Komutanım', 'Komutanlığ', 'ınız', 'a'],
    'rektor': ['Rektörüm', 'Rektörlüğ', 'ünüz', 'ö'],
    'koord': ['Koordinatörüm', 'Koordinatörlüğ', 'ünüz', 'ö'],
    'temsilci': ['Temsilcim', 'Temsilciliğ', 'iniz', 'e'],
    'gensek': ['Genel Sekreterim', 'Genel Sekreterliğ', 'iniz', 'e'],
    'yetkili': ['Yetkili', null, null, null],
  };

  // uyum -> [yönelme, çıkma, tamlayan, bulunma, -ca, belirtme]
  static const _ek = <String, List<String>>{
    'a': ['a', 'dan', 'ın', 'da', 'ca', 'ı'],
    'e': ['e', 'den', 'in', 'de', 'ce', 'i'],
    'o': ['a', 'dan', 'un', 'da', 'ca', 'u'],
    'ö': ['e', 'den', 'ün', 'de', 'ce', 'ü'],
  };
  static const _harf = 'A-Za-zÇĞİIÖŞÜçğıöşü';
  static const _kokRe =
      'Bakanlığ|Genel Müdürlüğ|Başkanlığ|Müşavirliğ|Komutanlığ|Rektörlüğ|Koordinatörlüğ|Temsilciliğ|Genel Sekreterliğ';
  static const _eskiEk = <String, int>{
    'a': 0,
    'e': 0,
    'dan': 1,
    'den': 1,
    'ın': 2,
    'in': 2,
    'un': 2,
    'ün': 2,
    'da': 3,
    'de': 3,
    'ca': 4,
    'ce': 4,
    'ı': 5,
    'i': 5,
    'u': 5,
    'ü': 5,
  };

  static final _selamRe = RegExp(
    'Sayın (${_hitap.values.map((h) => h[0]).join('|')})(?![$_harf])',
  );
  static final _iyelikRe = RegExp(
    '($_kokRe)(ınız|iniz|unuz|ünüz)(a|e|dan|den|ın|in|un|ün|da|de|ca|ce|ı|i|u|ü)?(?![$_harf])',
  );
  static final _bakanligiRe = RegExp(
    'Bakanlığ(ınız)(a|dan|ın|da|ca|ı)?(?![$_harf])',
  );

  /// Ünvan esas alınır (ad kişi adına çevrilmiş olabilir); ünvan yoksa kurum adının sonuna bakılır.
  static String hitapTuru(String ad, String unvan) {
    var u = unvan.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    if (u.isEmpty) u = ad.trim();
    bool e(String desen) => RegExp(desen, caseSensitive: false).hasMatch(u);
    if (e(r'(^|\s)Bakan(ı| Yardımcısı)?$')) return 'bakan';
    if (e(r'Genel Müdür(lüğü|ü)?$')) return 'genelmd';
    if (e(r'Genel Sekreter(liği|i)?$')) return 'gensek';
    if (e(r'Müdür(lüğü|ü)?$')) return 'mudur';
    if (e(r'Başkan(lığı|ı)?$')) return 'baskan';
    if (e(r'Müşavir(liği|i)?$')) return 'musavir';
    if (e(r'Komutan(lığı|ı)?$')) return 'komutan';
    if (e(r'Rektör(lüğü|ü)?$')) return 'rektor';
    if (e(r'Koordinatör(lüğü|ü)?$')) return 'koord';
    if (e(r'Temsilci(liği|si)?$')) return 'temsilci';
    return 'yetkili';
  }

  static String hitapDonustur(String metin, String tur) {
    final h = _hitap[tur];
    if (h == null || metin.isEmpty) return metin;
    var s = metin.replaceAllMapped(_selamRe, (_) => 'Sayın ${h[0]}');
    final kok = h[1];
    if (kok != null) {
      final iyelik = h[2]!;
      final uyum = _ek[h[3]]!;
      s = s.replaceAllMapped(_iyelikRe, (m) {
        var yeni = '$kok$iyelik';
        final ek = m.group(3);
        if (ek != null) {
          final i = _eskiEk[ek];
          yeni += i == null ? ek : uyum[i];
        }
        return yeni;
      });
      if (tur != 'bakan') {
        s = s.replaceAllMapped(_bakanligiRe, (m) {
          var y = '$kok$iyelik';
          final ek = m.group(2);
          if (ek != null) y += uyum[_eskiEk[ek]!];
          return y;
        });
      }
    }
    return s;
  }
}
