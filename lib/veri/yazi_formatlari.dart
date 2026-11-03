/// Türkçe karakterleri katlayıp küçültür: "Işık" ile "isik" aynı aramada bulunur.
String aramaMetni(String s) {
  const kat = {
    'İ': 'i',
    'I': 'i',
    'ı': 'i',
    'Ç': 'c',
    'ç': 'c',
    'Ğ': 'g',
    'ğ': 'g',
    'Ö': 'o',
    'ö': 'o',
    'Ş': 's',
    'ş': 's',
    'Ü': 'u',
    'ü': 'u',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(kat[c] ?? c.toLowerCase());
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Web'deki zengin metin (HTML) alanını düz metne çevirir (liste/ayrıntı gösterimi ve mobil düzenleme için).
String htmlDuz(String? html) {
  if (html == null || html.isEmpty) return '';
  var s = html
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|li|h[1-6])\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '');
  const varlik = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
  };
  varlik.forEach((k, v) => s = s.replaceAll(k, v));
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Mobilde yazılan düz metni sunucunun beklediği basit HTML'e çevirir (her satır bir paragraf).
String duzHtml(String metin) {
  final t = metin.trim();
  if (t.isEmpty) return '';
  String kac(String x) => x
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return t.split(RegExp(r'\r?\n')).map((l) => '<p>${kac(l)}</p>').join();
}

/// Türkçe büyük harf: i → İ, ı → I (Dart'ın varsayılanı bunları yanlış çevirir).
String trBuyuk(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Türkçe alfabe sırasına göre sıralanabilen anahtar: "Çelik" C'den sonra gelir, "Ömer" O'dan sonra, "Işık" H'den sonra (I harfi ı, İ harfi i).
String siraAnahtari(String s) {
  const alfabe = 'abcçdefgğhıijklmnoöprsştuüvyz';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final k = c == 'I' ? 'ı' : (c == 'İ' ? 'i' : c.toLowerCase());
    final i = alfabe.indexOf(k);
    if (i >= 0) {
      b.write(String.fromCharCode(0x61 + i));
    } else if (RegExp(r'[0-9]').hasMatch(k)) {
      b.write(k);
    } else if (k == ' ') {
      b.write(' ');
    } else if (RegExp(r'[a-z]').hasMatch(k)) {
      b.write(String.fromCharCode(0x61 + alfabe.length)); // q, w, x en sona
    }
  }
  return b.toString().trim();
}

/// Rehber harf sekmesi: ilk harf (Türkçe büyük), rakamla başlıyorsa "0-9", diğerleri "#".
String ilkHarf(String ad) {
  final t = ad.trim();
  if (t.isEmpty) return '#';
  final h = trBuyuk(t.substring(0, 1));
  if (RegExp(r'[0-9]').hasMatch(h)) return '0-9';
  if (RegExp(r'^[A-ZÇĞİÖŞÜ]$').hasMatch(h)) return h;
  return '#';
}
