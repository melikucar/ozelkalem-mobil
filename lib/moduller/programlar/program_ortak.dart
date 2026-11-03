import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/program.dart';

const trAylar = [
  '',
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

const trAylarKisa = [
  '',
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

/// 1 = Pazartesi … 7 = Pazar.
const trGunler = [
  '',
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

const trGunlerKisa = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

String saatYaz(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "30 Ekim 2026 Cuma"
String uzunGunYaz(DateTime d) =>
    '${d.day} ${trAylar[d.month]} ${d.year} ${trGunler[d.weekday]}';

/// "30 Ekim Cuma"
String gunBaslikYaz(DateTime d) =>
    '${d.day} ${trAylar[d.month]} ${trGunler[d.weekday]}';

/// "2 sa 30 dk", "45 dk", "3 gün"
String sureYaz(Duration s) {
  final dk = s.inMinutes;
  if (dk >= 1440 && dk % 1440 == 0) return '${dk ~/ 1440} gün';
  if (dk >= 60) {
    final sa = dk ~/ 60;
    final k = dk % 60;
    return k == 0 ? '$sa sa' : '$sa sa $k dk';
  }
  return '$dk dk';
}

/// Program [gun] gününe değiyor mu (gün içinde başlıyor, bitiyor ya da kapsıyor).
bool programGundeMi(Program p, DateTime gun) {
  final g = gunBasi(gun);
  final ertesi = g.add(const Duration(days: 1));
  if (!p.bas.isBefore(ertesi)) return false;
  return p.bit.isAfter(g) || ayniGun(p.bas, g);
}

/// Pazartesi başlangıçlı hafta başı.
DateTime haftaBasi(DateTime d) {
  final g = gunBasi(d);
  return g.subtract(Duration(days: g.weekday - 1));
}

/// Programın şu anki durumu: şimdi / bitti / yaklaşıyor.
enum ProgramZamani { gecmis, suan, gelecek }

ProgramZamani programZamaniDurumu(Program p, [DateTime? simdi]) {
  final n = simdi ?? DateTime.now();
  if (p.tumGun) {
    final g = gunBasi(p.bas);
    if (ayniGun(n, g)) return ProgramZamani.suan;
    return n.isAfter(g) ? ProgramZamani.gecmis : ProgramZamani.gelecek;
  }
  if (n.isBefore(p.bas)) return ProgramZamani.gelecek;
  if (n.isAfter(p.bit)) return ProgramZamani.gecmis;
  return ProgramZamani.suan;
}

/// "35 dk sonra", "2 sa sonra", "Yarın 10:00" gibi kısa kalan süre yazısı (yalnızca yaklaşan programlar için).
String kalanYazi(Program p, [DateTime? simdi]) {
  final n = simdi ?? DateTime.now();
  final fark = p.bas.difference(n);
  if (fark.isNegative) return '';
  if (fark.inMinutes < 1) return 'Şimdi başlıyor';
  if (fark.inMinutes < 60) return '${fark.inMinutes} dk sonra';
  if (fark.inHours < 24) return '${fark.inHours} sa sonra';
  final gun = gunBasi(p.bas).difference(gunBasi(n)).inDays;
  if (gun == 1) return 'Yarın ${saatYaz(p.bas)}';
  return '${p.bas.day} ${trAylarKisa[p.bas.month]}';
}

List<BoxShadow> programGolgesi(BuildContext context) {
  final acik = Theme.of(context).brightness == Brightness.light;
  return [
    BoxShadow(
      color: (acik ? Marka.lacivert : Colors.black).withValues(
        alpha: acik ? 0.08 : 0.35,
      ),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ];
}

/// Bölüm başlığı: ikon rozeti + büyük harf başlık (detay/form kartları için).
class ProgramKutu extends StatelessWidget {
  const ProgramKutu({
    super.key,
    required this.baslik,
    required this.ikon,
    required this.cocuk,
    this.sag,
  });

  final String baslik;
  final IconData ikon;
  final Widget cocuk;
  final Widget? sag;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vurgu = tema.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: programGolgesi(context),
        ),
        child: Material(
          color: tema.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: vurgu.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(ikon, size: 18, color: vurgu),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        trBuyuk(baslik),
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    ?sag,
                  ],
                ),
                const SizedBox(height: 14),
                cocuk,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
