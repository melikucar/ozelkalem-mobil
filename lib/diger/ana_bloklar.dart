import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/api_istemci.dart';
import '../tema/tema.dart';
import '../veri/yazi_formatlari.dart';
import '../veri/tarih_yardimci.dart';

/// Binlik ayraçlı sayı: 12345 → 12.345 (web ana sayfasındaki gibi).
String binlik(num n) => n.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => '.',
);

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _liste(Object? v) => [
  for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map),
];

List<BoxShadow> _golge(BuildContext context) {
  final acik = Theme.of(context).brightness == Brightness.light;
  return [
    BoxShadow(
      color: (acik ? Marka.lacivert : Colors.black).withValues(
        alpha: acik ? 0.08 : 0.35,
      ),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Ana sayfadaki blok kartı: ikon rozetli büyük harf başlık, isteğe bağlı sağ yazı.
class AnaKart extends StatelessWidget {
  const AnaKart({
    super.key,
    required this.baslik,
    required this.ikon,
    required this.cocuk,
    this.sag,
    this.renk,
  });

  final String baslik;
  final IconData ikon;
  final Widget cocuk;
  final String? sag;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vurgu = renk ?? tema.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: _golge(context),
        ),
        child: Material(
          color: tema.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
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
                    if (sag != null)
                      Text(
                        sag!,
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: tema.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                cocuk,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sayıyı 0'dan hedefe doğru sayarak gösterir (web'deki rakam animasyonu).
class _SayiAnim extends StatelessWidget {
  const _SayiAnim(this.deger, {required this.stil});

  final int deger;
  final TextStyle? stil;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(deger),
    tween: Tween(begin: 0, end: deger.toDouble()),
    duration: const Duration(milliseconds: 1100),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text(binlik(v), style: stil),
  );
}

/// v7'deki dikey rakam bloğu: büyük "Toplam talep" kartı (bugün/dün kayıtlarıyla) ve altında renkli sayı kutuları.
class RakamlarKarti extends StatelessWidget {
  const RakamlarKarti({
    super.key,
    required this.veri,
    this.talepGit,
    this.git,
    this.modulVar,
  });

  final Map<String, dynamic> veri;
  final VoidCallback? talepGit;

  /// Karta dokununca ilgili modüle geçer (sayfa anahtarıyla); [modulVar] yetkisi olmayan kart dokunulamaz.
  final void Function(String modul)? git;
  final bool Function(String modul)? modulVar;

  /// kutu anahtarı → (sayfa anahtarı, yetki modülü)
  static const _hedef = {
    'program': ('ajanda', 'ajanda'),
    'randevu': ('randevular', 'ajanda'),
    'gorusme': ('telefonlar', 'telefonlar'),
    'rehber': ('telefonlar', 'telefonlar'),
    'faaliyet': ('faaliyetler', 'faaliyetler'),
    'ust_yazi': ('yazismalar', 'yazismalar'),
  };

  static const _kutular = [
    (
      'program',
      'Programlar',
      'program kaydedildi',
      Icons.calendar_month_rounded,
      Color(0xFF0CABB5),
    ),
    (
      'randevu',
      'Randevular',
      'randevu kaydedildi',
      Icons.edit_calendar_rounded,
      Color(0xFF636E82),
    ),
    (
      'gorusme',
      'Telefon görüşmeleri',
      'kişiyle görüşüldü',
      Icons.phone_in_talk_rounded,
      Color(0xFFE0701A),
    ),
    (
      'rehber',
      'Telefon rehberi',
      'telefon kaydı yapıldı',
      Icons.menu_book_rounded,
      Color(0xFF1B7FD1),
    ),
    (
      'faaliyet',
      'Faaliyetler',
      'faaliyet kaydedildi',
      Icons.folder_open_rounded,
      Color(0xFFC0182B),
    ),
    (
      'ust_yazi',
      'Üst yazılar',
      'üst yazı yazıldı',
      Icons.history_edu_rounded,
      Color(0xFFD9960B),
    ),
  ];

  VoidCallback? _tiklama(String anahtar) {
    final h = _hedef[anahtar];
    if (h == null || git == null) return null;
    if (modulVar != null && !modulVar!(h.$2)) return null;
    return () => git!(h.$1);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final kutular = [
      for (final k in _kutular)
        if (veri[k.$1] != null) k,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (veri['toplam_talep'] != null)
            GestureDetector(
              onTap: talepGit,
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Marka.lacivert2, Color(0xFF0A4DB8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Marka.mavi.withValues(alpha: 0.28),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -14,
                      top: -10,
                      child: Icon(
                        Icons.show_chart_rounded,
                        size: 96,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'TOPLAM TALEP',
                            style: tema.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFC3CFDE),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                          _SayiAnim(
                            _i(veri['toplam_talep']),
                            stil: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Mini(
                                    _i(veri['bugun']),
                                    'Bugün kaydedilen',
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 24,
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                Expanded(
                                  child: _Mini(
                                    _i(veri['dun']),
                                    'Dün kaydedilen',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (kutular.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final sutun = c.maxWidth >= 560 ? 3 : 2;
                final w = (c.maxWidth - 12 * (sutun - 1)) / sutun;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final k in kutular)
                      SizedBox(
                        width: w,
                        height: 108,
                        child: _RakamKutusu(
                          sayi: _i(veri[k.$1]),
                          baslik: k.$2,
                          alt: k.$3,
                          ikon: k.$4,
                          renk: k.$5,
                          tikla: _tiklama(k.$1),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.sayi, this.yazi);

  final int sayi;
  final String yazi;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SayiAnim(
        sayi,
        stil: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      Text(
        yazi,
        style: const TextStyle(color: Color(0xFFC3CFDE), fontSize: 11),
      ),
    ],
  );
}

class _RakamKutusu extends StatelessWidget {
  const _RakamKutusu({
    required this.sayi,
    required this.baslik,
    required this.alt,
    required this.ikon,
    required this.renk,
    this.tikla,
  });

  final VoidCallback? tikla;
  final int sayi;
  final String baslik;
  final String alt;
  final IconData ikon;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: _golge(context),
      ),
      child: Material(
        color: tema.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tikla,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 4,
                child: ColoredBox(color: renk),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 12, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trBuyuk(baslik),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: renk.withValues(alpha: acik ? 0.13 : 0.24),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(ikon, size: 21, color: renk),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _SayiAnim(
                                  sayi,
                                  stil: tema.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: renk,
                                    height: 1.05,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              Text(
                                alt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.bodySmall?.copyWith(
                                  color: tema.colorScheme.onSurfaceVariant,
                                  height: 1.2,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _gunYazisi(int gun) => gun <= 0
    ? 'Bugün'
    : gun == 1
    ? 'Yarın'
    : '$gun gün kaldı';

Widget _rozet(BuildContext context, IconData ikon, String yazi, Color renk) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 13, color: renk),
          const SizedBox(width: 5),
          Text(
            yazi,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: renk,
            ),
          ),
        ],
      ),
    );

Widget _bosYazi(BuildContext context, String yazi) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Center(
    child: Text(
      yazi,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    ),
  ),
);

/// Ortak satır: soldaki yuvarlak rozet, iki satır metin, sağda isteğe bağlı etiket.
class _Satir extends StatelessWidget {
  const _Satir({
    required this.sol,
    required this.baslik,
    this.alt,
    this.sag,
    this.tikla,
    this.son = false,
  });

  final Widget sol;
  final String baslik;
  final String? alt;
  final Widget? sag;
  final VoidCallback? tikla;
  final bool son;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: tikla,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: son
              ? null
              : Border(
                  bottom: BorderSide(
                    color: tema.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
        ),
        child: Row(
          children: [
            sol,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baslik,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (alt != null && alt!.isNotEmpty)
                    Text(
                      alt!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (sag != null) ...[const SizedBox(width: 8), sag!],
          ],
        ),
      ),
    );
  }
}

Widget _daire(IconData ikon, Color renk) => Container(
  width: 38,
  height: 38,
  decoration: BoxDecoration(
    color: renk.withValues(alpha: 0.14),
    shape: BoxShape.circle,
  ),
  child: Icon(ikon, size: 19, color: renk),
);

/// v7 "Talep hatırlatıcı": yaklaşan hatırlatıcılar, aciliyete göre renkli.
class HatirlaticiBlok extends StatelessWidget {
  const HatirlaticiBlok({super.key, required this.veri, required this.ac});

  final Map<String, dynamic> veri;
  final void Function(int no) ac;

  @override
  Widget build(BuildContext context) {
    final liste = _liste(veri['liste']);
    final bugun = _i(veri['bugun']);
    final hafta = _i(veri['hafta']);
    return AnaKart(
      baslik: 'Talep hatırlatıcı',
      ikon: Icons.notifications_active_outlined,
      renk: const Color(0xFFE0701A),
      sag: _i(veri['toplam']) > 0 ? '${_i(veri['toplam'])} hatırlatıcı' : null,
      cocuk: liste.isEmpty
          ? _bosYazi(context, 'Yaklaşan hatırlatıcı yok')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bugun > 0 || hafta > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (bugun > 0)
                          _rozet(
                            context,
                            Icons.bolt_rounded,
                            '$bugun bugün',
                            const Color(0xFFC0182B),
                          ),
                        if (hafta > 0)
                          _rozet(
                            context,
                            Icons.date_range_rounded,
                            '$hafta bu hafta',
                            const Color(0xFFE0701A),
                          ),
                      ],
                    ),
                  ),
                for (var i = 0; i < liste.length; i++)
                  _Satir(
                    son: i == liste.length - 1,
                    tikla: () => ac(_i(liste[i]['no'])),
                    sol: _daire(
                      Icons.alarm_rounded,
                      _i(liste[i]['gun']) <= 0
                          ? const Color(0xFFC0182B)
                          : _i(liste[i]['gun']) <= 7
                          ? const Color(0xFFE0701A)
                          : const Color(0xFF1B7FD1),
                    ),
                    baslik: trBuyuk('${liste[i]['ad']}'),
                    alt: uzunTarih('${liste[i]['tarih']}'.split(' ').first),
                    sag: Text(
                      _gunYazisi(_i(liste[i]['gun'])),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _i(liste[i]['gun']) <= 0
                            ? const Color(0xFFC0182B)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// v7 "Beklemede olan talepler": bekleme süresine göre renklenen kartlar.
class BekleyenBlok extends StatelessWidget {
  const BekleyenBlok({
    super.key,
    required this.veri,
    required this.ac,
    required this.hepsi,
  });

  final Map<String, dynamic> veri;
  final void Function(int no) ac;
  final VoidCallback hepsi;

  static Color _renk(int gun) => gun <= 7
      ? const Color(0xFF12A150)
      : gun <= 30
      ? const Color(0xFFE0A100)
      : const Color(0xFFC0182B);

  @override
  Widget build(BuildContext context) {
    final liste = _liste(veri['liste']).take(5).toList();
    final toplam = _i(veri['toplam']);
    return AnaKart(
      baslik: 'Beklemede olan talepler',
      ikon: Icons.hourglass_top_rounded,
      renk: const Color(0xFF636E82),
      sag: toplam > 0 ? 'Toplam $toplam' : null,
      cocuk: liste.isEmpty
          ? _bosYazi(context, 'Beklemede talep yok')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _rozet(
                        context,
                        Icons.circle,
                        '${_i(veri['yeni'])} yeni (≤7 gün)',
                        _renk(0),
                      ),
                      _rozet(
                        context,
                        Icons.circle,
                        '${_i(veri['orta'])} orta',
                        _renk(20),
                      ),
                      _rozet(
                        context,
                        Icons.circle,
                        '${_i(veri['eski'])} eski (>30 gün)',
                        _renk(40),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < liste.length; i++)
                  _Satir(
                    son: i == liste.length - 1,
                    tikla: () => ac(_i(liste[i]['no'])),
                    sol: _daire(
                      Icons.hourglass_empty_rounded,
                      _renk(_i(liste[i]['gun'])),
                    ),
                    baslik: trBuyuk('${liste[i]['ad']}'),
                    alt: [
                      '${liste[i]['kategori']}',
                      uzunTarih('${liste[i]['tarih']}'.split(' ').first),
                    ].where((e) => (e ?? '').isNotEmpty).join(' · '),
                    sag: Text(
                      _i(liste[i]['gun']) == 0
                          ? 'Bugün'
                          : '${_i(liste[i]['gun'])} gündür',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _renk(_i(liste[i]['gun'])),
                      ),
                    ),
                  ),
                _TumunuGor(tikla: hepsi, adet: toplam),
              ],
            ),
    );
  }
}

/// v7 "Son eklenen faaliyetler": tarih kutulu kompakt liste.
class FaaliyetBlok extends StatelessWidget {
  const FaaliyetBlok({
    super.key,
    required this.veri,
    required this.api,
    required this.hepsi,
    required this.ac,
  });

  final Map<String, dynamic> veri;
  final ApiIstemci api;
  final VoidCallback hepsi;
  final ValueChanged<int> ac;

  static const _ay = [
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

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final liste = _liste(veri['liste']).take(5).toList();
    const renk = Color(0xFFC0182B);
    return AnaKart(
      baslik: 'Son eklenen faaliyetler',
      ikon: Icons.campaign_outlined,
      renk: renk,
      cocuk: liste.isEmpty
          ? _bosYazi(context, 'Faaliyet kaydı bulunmamaktadır')
          : Column(
              children: [
                for (var i = 0; i < liste.length; i++)
                  Builder(
                    builder: (context) {
                      final t = DateTime.tryParse('${liste[i]['tarih']}');
                      return _Satir(
                        son: i == liste.length - 1,
                        tikla: () => ac(_i(liste[i]['no'])),
                        sol: Container(
                          width: 46,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: renk.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: t == null
                              ? const Icon(Icons.event, color: renk, size: 20)
                              : Column(
                                  children: [
                                    Text(
                                      '${t.day}',
                                      style: tema.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: renk,
                                            height: 1.1,
                                          ),
                                    ),
                                    Text(
                                      _ay[t.month],
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: renk,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        baslik: '${liste[i]['adi']}',
                        alt: '${liste[i]['kategori']}',
                        sag: liste[i]['resim'] == true
                            ? FaaliyetKucukResim(
                                api: api,
                                no: _i(liste[i]['no']),
                              )
                            : null,
                      );
                    },
                  ),
                _TumunuGor(tikla: hepsi),
              ],
            ),
    );
  }
}

/// v7 "Telefon görüşmeleri": son görüşmeler, giden/gelen yönü ve sonucuyla.
class GorusmeBlok extends StatelessWidget {
  const GorusmeBlok({super.key, required this.veri, required this.hepsi});

  final Map<String, dynamic> veri;
  final VoidCallback hepsi;

  @override
  Widget build(BuildContext context) {
    final liste = _liste(veri['liste']).take(5).toList();
    final ok = _i(veri['ok']);
    final yok = _i(veri['yok']);
    return AnaKart(
      baslik: 'Telefon görüşmeleri',
      ikon: Icons.phone_in_talk_outlined,
      renk: const Color(0xFFE0701A),
      sag: liste.isEmpty ? null : 'Son ${liste.length} görüşme',
      cocuk: liste.isEmpty
          ? _bosYazi(context, 'Telefon görüşme kaydı bulunmamaktadır')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _rozet(
                        context,
                        Icons.check_circle_rounded,
                        '$ok görüşüldü',
                        const Color(0xFF12A150),
                      ),
                      _rozet(
                        context,
                        Icons.cancel_rounded,
                        '$yok ulaşılamadı',
                        const Color(0xFFC0182B),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < liste.length; i++)
                  Builder(
                    builder: (context) {
                      final g = liste[i];
                      final sonuc = _i(g['sonuc']);
                      final renk = sonuc == 1
                          ? const Color(0xFF12A150)
                          : sonuc == -1
                          ? const Color(0xFFC0182B)
                          : Theme.of(context).colorScheme.outline;
                      final giden = g['giden'] == true;
                      return _Satir(
                        son: i == liste.length - 1,
                        sol: _daire(
                          giden
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          renk,
                        ),
                        baslik: trBuyuk('${g['ad']}'),
                        alt: [
                          if ('${g['konu']}'.isNotEmpty) '${g['konu']}',
                          uzunZaman('${g['tarih']}'),
                        ].whereType<String>().join(' · '),
                        sag: Text(
                          giden ? 'GİDEN' : 'GELEN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: renk,
                            letterSpacing: 0.3,
                          ),
                        ),
                      );
                    },
                  ),
                _TumunuGor(tikla: hepsi),
              ],
            ),
    );
  }
}

/// Bölümler yüklenirken kısa bir iskelet.
class BlokIskeleti extends StatelessWidget {
  const BlokIskeleti({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      children: [
        for (final h in const [150.0, 100.0, 140.0])
          Container(
            height: h,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: tema.colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    );
  }
}

/// Faaliyetin ilk resminin küçük önizlemesi. Sunucu yeniden boyutlandırıp verir; oturum boyunca bellekte saklanır.
class FaaliyetKucukResim extends StatefulWidget {
  const FaaliyetKucukResim({super.key, required this.api, required this.no});

  final ApiIstemci api;
  final int no;

  static final Map<int, Uint8List> _onbellek = {};

  @override
  State<FaaliyetKucukResim> createState() => _FaaliyetKucukResimState();
}

class _FaaliyetKucukResimState extends State<FaaliyetKucukResim> {
  Uint8List? _bayt;
  bool _hata = false;

  @override
  void initState() {
    super.initState();
    _bayt = FaaliyetKucukResim._onbellek[widget.no];
    if (_bayt == null) _yukle();
  }

  Future<void> _yukle() async {
    try {
      final b = await widget.api.indir('faaliyetler/resim?no=${widget.no}');
      FaaliyetKucukResim._onbellek[widget.no] = b;
      if (mounted) setState(() => _bayt = b);
    } catch (_) {
      if (mounted) setState(() => _hata = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    if (_hata) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        color: tema.colorScheme.onSurface.withValues(alpha: 0.06),
        child: _bayt == null
            ? null
            : Image.memory(
                _bayt!,
                fit: BoxFit.cover,
                cacheWidth: 160,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
      ),
    );
  }
}

/// v7 sağ paneldeki "Talep durumları": renk noktalı, adetli ve mini çubuklu liste; dokununca o durumdaki talepler açılır.
class DurumlarBlok extends StatelessWidget {
  const DurumlarBlok({super.key, required this.veri, required this.ac});

  final Map<String, dynamic> veri;
  final void Function(int durumNo) ac;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final liste = _liste(veri['liste']);
    final enCok = liste.fold<int>(1, (a, d) => math.max(a, _i(d['sayi'])));
    Color renkOf(Map<String, dynamic> d) {
      final h = '${d['renk']}';
      if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(h)) {
        return Color(int.parse('FF${h.substring(1)}', radix: 16));
      }
      return tema.colorScheme.outline;
    }

    return AnaKart(
      baslik: 'Talep durumları',
      ikon: Icons.donut_small_rounded,
      renk: const Color(0xFF1B7FD1),
      sag: binlik(_i(veri['toplam'])),
      cocuk: liste.isEmpty
          ? _bosYazi(context, 'Durum tanımı yok')
          : Column(
              children: [
                for (var i = 0; i < liste.length; i++)
                  InkWell(
                    onTap: () => ac(_i(liste[i]['no'])),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: renkOf(liste[i]),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${liste[i]['adi']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                binlik(_i(liste[i]['sayi'])),
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: 0,
                                end: _i(liste[i]['sayi']) == 0
                                    ? 0
                                    : math.max(
                                        0.04,
                                        _i(liste[i]['sayi']) / enCok,
                                      ),
                              ),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, _) => LinearProgressIndicator(
                                value: v,
                                minHeight: 5,
                                color: renkOf(liste[i]),
                                backgroundColor: renkOf(liste[i])
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

Color _hexRenk(String? h, Color yedek) {
  if (h != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(h)) {
    return Color(int.parse('FF${h.substring(1)}', radix: 16));
  }
  return yedek;
}

DateTime? _zaman(Object? v) => DateTime.tryParse('$v'.replaceFirst(' ', 'T'));

String _saat(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// v7 "Aylık takvim" + "Program takvimi": ay ızgarası (programlı günlerde nokta), Bugün/Yarın/Bu hafta/Bu ay sekmeleri
/// ve zaman sırasıyla program akışı. Bir güne dokununca o günün programları listelenir.
class TakvimBlok extends StatefulWidget {
  const TakvimBlok({super.key, required this.veri, required this.ac});

  final Map<String, dynamic> veri;
  final ValueChanged<int> ac;

  @override
  State<TakvimBlok> createState() => _TakvimBlokState();
}

class _TakvimBlokState extends State<TakvimBlok> {
  int _sekme = 0; // 0 bugün, 1 yarın, 2 hafta, 3 ay
  DateTime? _gun; // takvimden seçilen gün (sekmeyi geçersiz kılar)

  static const _aylar = [
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
  static const _gunler = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  static const _gunAdlari = [
    '',
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  DateTime get _bugun =>
      DateTime.tryParse('${widget.veri['bugun']}') ?? DateTime.now();

  List<({Map<String, dynamic> p, DateTime bas, DateTime bit})> get _hepsi {
    final cikti = <({Map<String, dynamic> p, DateTime bas, DateTime bit})>[];
    for (final p in _liste(widget.veri['liste'])) {
      final b = _zaman(p['bas']);
      if (b == null) continue;
      cikti.add((p: p, bas: b, bit: _zaman(p['bit']) ?? b));
    }
    return cikti;
  }

  bool _ayniGun(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<({Map<String, dynamic> p, DateTime bas, DateTime bit})> _sekmeListesi(
    int s,
  ) {
    final bugun = DateTime(_bugun.year, _bugun.month, _bugun.day);
    final yarin = bugun.add(const Duration(days: 1));
    final haftaIlk = bugun.subtract(Duration(days: bugun.weekday - 1));
    final haftaSon = haftaIlk.add(const Duration(days: 6));
    return _hepsi.where((e) {
      final g = DateTime(e.bas.year, e.bas.month, e.bas.day);
      return switch (s) {
        0 => g == bugun,
        1 => g == yarin,
        2 => !g.isBefore(haftaIlk) && !g.isAfter(haftaSon),
        _ => g.year == bugun.year && g.month == bugun.month,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vurgu = tema.colorScheme.primary;
    final bugun = DateTime(_bugun.year, _bugun.month, _bugun.day);
    final hepsi = _hepsi;
    final secim = _gun;
    final liste = secim != null
        ? hepsi.where((e) => _ayniGun(e.bas, secim)).toList()
        : _sekmeListesi(_sekme);

    // Ay ızgarası
    final ilk = DateTime(bugun.year, bugun.month, 1);
    final gunSayisi = DateTime(bugun.year, bugun.month + 1, 0).day;
    final bosluk = ilk.weekday - 1;
    final programGunleri = {
      for (final e in hepsi)
        if (e.bas.month == bugun.month) e.bas.day: true,
    };

    Widget hucre(int gun) {
      final d = DateTime(bugun.year, bugun.month, gun);
      final bugunMu = d == bugun;
      final secili = secim != null && _ayniGun(secim, d);
      final programli = programGunleri[gun] == true;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _gun = secili ? null : d),
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: secili
                  ? vurgu
                  : bugunMu
                  ? vurgu.withValues(alpha: 0.14)
                  : null,
              border: bugunMu && !secili ? Border.all(color: vurgu) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$gun',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: bugunMu || programli
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: secili ? Colors.white : tema.colorScheme.onSurface,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: programli
                        ? (secili ? Colors.white : const Color(0xFFE0701A))
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hucreler = <Widget>[
      for (var i = 0; i < bosluk; i++) const SizedBox.shrink(),
      for (var g = 1; g <= gunSayisi; g++) hucre(g),
    ];

    const etiketler = ['Bugün', 'Yarın', 'Bu hafta', 'Bu ay'];
    String gunBasligi(DateTime d) =>
        '${d.day} ${_aylar[d.month]} ${_gunAdlari[d.weekday]}';

    final satirlar = <Widget>[];
    String? son;
    final grupla = secim == null && _sekme >= 2;
    for (var i = 0; i < liste.length; i++) {
      final e = liste[i];
      if (grupla) {
        final baslik = gunBasligi(e.bas);
        if (baslik != son) {
          son = baslik;
          final bugunMu = _ayniGun(e.bas, bugun);
          satirlar.add(
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                '${bugunMu ? 'Bugün · ' : ''}$baslik',
                style: tema.textTheme.labelMedium?.copyWith(
                  color: bugunMu ? vurgu : tema.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
      }
      final renk = _hexRenk('${e.p['renk']}', const Color(0xFF3788D8));
      final tumGun = e.bas.hour == 0 && e.bas.minute == 0 && e.bit == e.bas;
      final simdi = DateTime.now();
      final bitti = e.bit.isBefore(simdi) && _ayniGun(e.bas, bugun);
      final suan =
          !tumGun &&
          _ayniGun(e.bas, bugun) &&
          !simdi.isBefore(e.bas) &&
          !simdi.isAfter(e.bit);
      satirlar.add(
        _Satir(
          son: i == liste.length - 1,
          tikla: () => widget.ac(_i(e.p['no'])),
          sol: SizedBox(
            width: 48,
            child: Column(
              children: [
                Text(
                  tumGun ? 'Gün' : _saat(e.bas),
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: renk,
                    height: 1.1,
                  ),
                ),
                Text(
                  tumGun ? 'boyu' : (e.bit != e.bas ? _saat(e.bit) : ''),
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          baslik: '${e.p['adi']}',
          alt: [
            if ('${e.p['yer']}'.isNotEmpty) '${e.p['yer']}',
            if ('${e.p['durum']}'.isNotEmpty) '${e.p['durum']}',
          ].join(' · '),
          sag: suan
              ? _rozet(context, Icons.circle, 'ŞİMDİ', const Color(0xFF12A150))
              : bitti
              ? Text(
                  'Bitti',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        ),
      );
    }

    return AnaKart(
      baslik: 'Aylık takvim',
      ikon: Icons.calendar_month_rounded,
      renk: const Color(0xFF0CABB5),
      sag: '${_aylar[bugun.month]} ${bugun.year}',
      cocuk: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final g in _gunler)
                Expanded(
                  child: Center(
                    child: Text(
                      g,
                      style: tema.textTheme.labelSmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.15,
            children: hucreler,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${etiketler[i]}  ${_sekmeListesi(i).length}',
                      ),
                      selected: secim == null && _sekme == i,
                      onSelected: (_) => setState(() {
                        _sekme = i;
                        _gun = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (secim != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      gunBasligi(secim),
                      style: tema.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _gun = null),
                    child: const Text('Seçimi kaldır'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          if (satirlar.isEmpty)
            _bosYazi(
              context,
              secim != null
                  ? 'Bu gün için program yok'
                  : const [
                      'Bugün için program yok',
                      'Yarın için program yok',
                      'Bu hafta için program yok',
                      'Bu ay için program yok',
                    ][_sekme],
            )
          else
            Column(children: satirlar),
        ],
      ),
    );
  }
}

/// v7 "Randevular": kategori sekmeleri (adetli), durum etiketi renkli randevu satırları.
class RandevularBlok extends StatefulWidget {
  const RandevularBlok({
    super.key,
    required this.veri,
    required this.hepsi,
    required this.ac,
  });

  final Map<String, dynamic> veri;
  final VoidCallback hepsi;
  final ValueChanged<int> ac;

  @override
  State<RandevularBlok> createState() => _RandevularBlokState();
}

class _RandevularBlokState extends State<RandevularBlok> {
  int _kat = 0;

  Color _durumRengi(String d) {
    final x = d.toLowerCase();
    if (RegExp(r'onay|kabul|tamam|gerçekleş|yapıldı').hasMatch(x)) {
      return const Color(0xFF12A150);
    }
    if (RegExp(r'iptal|red|olumsuz|vazgeç').hasMatch(x)) {
      return const Color(0xFFC0182B);
    }
    if (RegExp(r'bekle|erte|talep').hasMatch(x)) {
      return const Color(0xFFE0A100);
    }
    return const Color(0xFF636E82);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final kategoriler = _liste(widget.veri['kategoriler']);
    if (kategoriler.isEmpty) {
      return AnaKart(
        baslik: 'Randevular',
        ikon: Icons.edit_calendar_rounded,
        renk: const Color(0xFF636E82),
        cocuk: _bosYazi(
          context,
          'Ana sayfada gösterilecek randevu kategorisi yok',
        ),
      );
    }
    final secili = _kat < kategoriler.length ? _kat : 0;
    final k = kategoriler[secili];
    final liste = _liste(k['liste']).take(5).toList();
    const ay = [
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
    return AnaKart(
      baslik: 'Randevular',
      ikon: Icons.edit_calendar_rounded,
      renk: const Color(0xFF636E82),
      sag: _i(k['toplam']) > liste.length
          ? 'Son ${liste.length} / ${_i(k['toplam'])}'
          : '${liste.length} randevu',
      cocuk: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < kategoriler.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${trBuyuk('${kategoriler[i]['adi']}')}  ${_i(kategoriler[i]['toplam'])}',
                      ),
                      selected: secili == i,
                      onSelected: (_) => setState(() => _kat = i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (liste.isEmpty)
            _bosYazi(context, 'Bu kategoride randevu yok')
          else
            for (var i = 0; i < liste.length; i++)
              Builder(
                builder: (context) {
                  final r = liste[i];
                  final t = _zaman(r['tarih']);
                  final durum = '${r['durum']}';
                  final renk = _durumRengi(durum);
                  return _Satir(
                    son: i == liste.length - 1,
                    tikla: () => widget.ac(_i(r['no'])),
                    sol: Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: renk.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: t == null
                          ? Icon(Icons.event, color: renk, size: 20)
                          : Column(
                              children: [
                                Text(
                                  '${t.day}',
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: renk,
                                    height: 1.1,
                                  ),
                                ),
                                Text(
                                  ay[t.month],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: renk,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    baslik: trBuyuk('${r['adi']}'),
                    alt: [
                      if ('${r['unvan']}'.isNotEmpty) '${r['unvan']}',
                      if (t != null && (t.hour != 0 || t.minute != 0)) _saat(t),
                      if ('${r['yer']}'.isNotEmpty) '${r['yer']}',
                    ].join(' · '),
                    sag: durum.isEmpty
                        ? null
                        : Text(
                            durum,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: renk,
                            ),
                          ),
                  );
                },
              ),
          _TumunuGor(tikla: widget.hepsi, adet: _i(k['toplam'])),
        ],
      ),
    );
  }
}

/// Blok altındaki "Tümünü gör" bağlantısı (sağ altta).
class _TumunuGor extends StatelessWidget {
  const _TumunuGor({required this.tikla, this.adet});

  final VoidCallback tikla;
  final int? adet;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      onPressed: tikla,
      child: Text(
        adet != null && adet! > 0 ? 'Tümünü gör ($adet)' : 'Tümünü gör',
      ),
    ),
  );
}
