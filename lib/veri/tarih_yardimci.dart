const _aylar = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// "2026-10-30" → 30 Ekim 2026. Geçersiz/boşsa null.
DateTime? _gecerli(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return (d == null || d.year < 1900)
      ? null
      : d; // "0000-00-00" gibi sıfır tarihler geçersizdir
}

String? uzunTarih(String? iso) {
  final d = _gecerli(iso);
  return d == null ? null : '${d.day} ${_aylar[d.month - 1]} ${d.year}';
}

/// Liste grupları için: Bugün / Dün / 28 Ekim 2026; tarihsizler "Tarihsiz".
String gunEtiketi(String? iso, {DateTime? simdi}) {
  final d = _gecerli(iso);
  if (d == null) return 'Tarihsiz';
  final n = simdi ?? DateTime.now();
  final bugun = DateTime(n.year, n.month, n.day);
  final fark = bugun.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (fark == 0) return 'Bugün';
  if (fark == 1) return 'Dün';
  return '${d.day} ${_aylar[d.month - 1]} ${d.year}';
}

/// "Bugün", "Dün", "3 gün önce", "2 hafta önce", "5 ay önce", "1 yıl önce"; geçersizse boş.
String goreliGun(String? iso, {DateTime? simdi}) {
  final d = _gecerli(iso);
  if (d == null) return '';
  final n = simdi ?? DateTime.now();
  final fark = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (fark <= 0) return 'Bugün';
  if (fark == 1) return 'Dün';
  if (fark < 7) return '$fark gün önce';
  if (fark < 30) return '${fark ~/ 7} hafta önce';
  if (fark < 365) return '${fark ~/ 30} ay önce';
  return '${fark ~/ 365} yıl önce';
}

/// Telefonu uluslararası biçime çevirir (WhatsApp / arama için): 0532… → 90532…
String telefonRakamlari(String tel) {
  var r = tel.replaceAll(RegExp(r'[^0-9]'), '');
  if (r.startsWith('00')) r = r.substring(2);
  if (r.startsWith('0')) r = '9$r';
  if (r.length == 10) r = '90$r';
  return r;
}

/// "2026-10-30 14:31:00" → "30 Ekim 2026 14:31". Geçersizse null.
String? uzunZaman(String? iso) {
  final d = _gecerli(iso?.replaceFirst(' ', 'T'));
  if (d == null) return null;
  String iki(int x) => x.toString().padLeft(2, '0');
  final saat = (iso!.length > 10 && (d.hour != 0 || d.minute != 0))
      ? ' ${iki(d.hour)}:${iki(d.minute)}'
      : '';
  return '${d.day} ${_aylar[d.month - 1]} ${d.year}$saat';
}
