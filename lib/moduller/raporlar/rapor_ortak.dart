import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../programlar/program_ortak.dart';

/// Web rapor panelleriyle aynı renk paleti.
const raporRenkleri = <Color>[
  Color(0xFFB71C2B),
  Color(0xFF1D6FB8),
  Color(0xFF1F8A5B),
  Color(0xFFC77D0A),
  Color(0xFF7B4FB3),
  Color(0xFF0F8B9C),
  Color(0xFFD9434F),
  Color(0xFF5D6B7A),
  Color(0xFFE0A100),
  Color(0xFF2F9E44),
];

const raporGunler = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const raporGunlerUzun = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

const _durumRenkleri = {
  'olumlu': Color(0xFF1F8A5B),
  'olumsuz': Color(0xFFB3202F),
  'beklemede': Color(0xFFC77D0A),
  'işlem yapılmadı': Color(0xFF6B7A99),
  'ilgili yere iletildi': Color(0xFF1D6FB8),
};

Color durumRengi(String ad, int i) =>
    _durumRenkleri[ad
        .toLowerCase()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')] ??
    raporRenkleri[(i + 4) % raporRenkleri.length];

/// 1234567.5 → "1.234.568" (ondalık: k basamak, virgüllü).
String sayi(Object? n, [int k = 0]) {
  final d = (n is num ? n : num.tryParse('${n ?? 0}') ?? 0).toDouble();
  final s = d.abs().toStringAsFixed(k);
  final parca = s.split('.');
  final ham = parca[0];
  final b = StringBuffer();
  for (var i = 0; i < ham.length; i++) {
    if (i > 0 && (ham.length - i) % 3 == 0) b.write('.');
    b.write(ham[i]);
  }
  var son = b.toString();
  if (k > 0) {
    final o = parca[1].replaceFirst(RegExp(r'0+$'), '');
    if (o.isNotEmpty) son = '$son,$o';
  }
  return (d < 0 && d != 0 ? '-' : '') + son;
}

num sayiDeger(Object? v) => v is num ? v : num.tryParse('${v ?? 0}') ?? 0;

List<Map<String, dynamic>> liste(Object? v) => [
  for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map),
];

/// "2026-10-30" → "30.10.2026" ya da kısa: "30 Eki".
String tarihTr(Object? s, {bool kisa = false}) {
  final t = '${s ?? ''}';
  if (t.length < 10) return '';
  final p = t.substring(0, 10).split('-');
  if (p.length != 3) return '';
  final ay = int.tryParse(p[1]) ?? 1;
  return kisa ? '${p[2]} ${trAylarKisa[ay]}' : '${p[2]}.${p[1]}.${p[0]}';
}

// ---------------------------------------------------------------------- süzgeç

const raporDonemleri = <(String, String)>[
  ('son30', 'Son 30 gün'),
  ('bu_ay', 'Bu ay'),
  ('gecen_ay', 'Geçen ay'),
  ('son90', 'Son 90 gün'),
  ('son365', 'Son 12 ay'),
  ('bu_yil', 'Bu yıl'),
  ('gecen_yil', 'Geçen yıl'),
  ('tumu', 'Tümü'),
];

String donemAdi(String d) => switch (d) {
  'tumu' => 'Tüm zamanlar',
  'ozel' => 'Özel aralık',
  _ => raporDonemleri.firstWhere((x) => x.$1 == d, orElse: () => ('', d)).$2,
};

class RaporFiltre {
  const RaporFiltre({
    this.donem = 'son365',
    this.bas,
    this.bit,
    this.kat = 0,
    this.durum = 0,
    this.yer = 0,
    this.il = 0,
    this.karsilastir = true,
  });

  final String donem;
  final DateTime? bas;
  final DateTime? bit;
  final int kat;
  final int durum;
  final int yer;
  final int il;
  final bool karsilastir;

  /// Dönem dışındaki etkin süzgeç sayısı (+ varsayılan dönem dışındaysa 1).
  int get etkin =>
      (kat > 0 ? 1 : 0) +
      (durum > 0 ? 1 : 0) +
      (yer > 0 ? 1 : 0) +
      (il > 0 ? 1 : 0);

  bool get varsayilan => etkin == 0 && donem == 'son365';

  RaporFiltre kopya({
    String? donem,
    DateTime? bas,
    DateTime? bit,
    int? kat,
    int? durum,
    int? yer,
    int? il,
    bool? karsilastir,
  }) => RaporFiltre(
    donem: donem ?? this.donem,
    bas: donem != null && donem != 'ozel' ? null : (bas ?? this.bas),
    bit: donem != null && donem != 'ozel' ? null : (bit ?? this.bit),
    kat: kat ?? this.kat,
    durum: durum ?? this.durum,
    yer: yer ?? this.yer,
    il: il ?? this.il,
    karsilastir: karsilastir ?? this.karsilastir,
  );

  static String _gun(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> get sorgu => {
    'donem': donem,
    if (donem == 'ozel' && bas != null && bit != null) ...{
      'bas': _gun(bas!),
      'bit': _gun(bit!),
    },
    'kat': '$kat',
    'durum': '$durum',
    'yer': '$yer',
    'il': '$il',
  };
}

// ---------------------------------------------------------------------- küçük bileşenler

/// Önceki döneme göre değişim rozeti (web ile aynı kural: [ters] true ise artış kötüdür).
class DeltaRozet extends StatelessWidget {
  const DeltaRozet({
    super.key,
    required this.simdi,
    required this.once,
    this.ters = false,
  });

  final num simdi;
  final num? once;
  final bool ters;

  @override
  Widget build(BuildContext context) {
    if (once == null) return const SizedBox.shrink();
    if (once == 0) {
      return simdi > 0
          ? _rozet(context, 'yeni', null, null)
          : const SizedBox.shrink();
    }
    final y = (simdi - once!) * 100 / once!;
    final art = y > 0.05;
    final azal = y < -0.05;
    final renk = (!art && !azal)
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : ((art != ters) ? const Color(0xFF1F8A5B) : const Color(0xFFB3202F));
    return _rozet(
      context,
      '%${sayi(y.abs(), 1)}',
      art
          ? Icons.arrow_upward_rounded
          : (azal ? Icons.arrow_downward_rounded : Icons.arrow_forward_rounded),
      renk,
    );
  }

  Widget _rozet(BuildContext context, String m, IconData? ikon, Color? renk) {
    final c = renk ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) Icon(ikon, size: 11, color: c),
          if (ikon != null) const SizedBox(width: 2),
          Text(
            m,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class KpiVeri {
  const KpiVeri({
    required this.ad,
    required this.ikon,
    required this.renk,
    required this.deger,
    this.delta,
    this.alt = '',
    this.spark,
  });

  final String ad;
  final IconData ikon;
  final Color renk;
  final String deger;
  final Widget? delta;
  final String alt;
  final List<num>? spark;
}

/// İki sütunlu KPI kartları (ikon, değer, değişim, küçük trend çizgisi).
class KpiIzgarasi extends StatelessWidget {
  const KpiIzgarasi({super.key, required this.kartlar});

  final List<KpiVeri> kartlar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final k in kartlar) SizedBox(width: w, child: _KpiKarti(k)),
          ],
        );
      },
    );
  }
}

class _KpiKarti extends StatelessWidget {
  const _KpiKarti(this.k);

  final KpiVeri k;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: programGolgesi(context),
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(height: 3, color: k.renk),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: k.renk.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(k.ikon, size: 16, color: k.renk),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          k.ad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      k.deger,
                      style: tema.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (k.delta != null) k.delta!,
                      if (k.alt.isNotEmpty)
                        Text(
                          k.alt,
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                  if (k.spark != null && k.spark!.length > 1) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 30,
                      child: _MiniCizgi(veri: k.spark!, renk: k.renk),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCizgi extends StatelessWidget {
  const _MiniCizgi({required this.veri, required this.renk});

  final List<num> veri;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < veri.length; i++)
                FlSpot(i.toDouble(), veri[i].toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            color: renk,
            barWidth: 1.8,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: renk.withValues(alpha: 0.13),
            ),
          ),
        ],
      ),
    );
  }
}

class Icgoru {
  const Icgoru(this.ikon, this.renk, this.metin);

  final IconData ikon;
  final Color renk;

  /// `**kalın**` işaretli metin.
  final String metin;
}

TextSpan _kalinli(String m, TextStyle? stil) {
  final parcalar = m.split('**');
  return TextSpan(
    children: [
      for (var i = 0; i < parcalar.length; i++)
        TextSpan(
          text: parcalar[i],
          style: i.isOdd ? stil?.copyWith(fontWeight: FontWeight.w800) : stil,
        ),
    ],
  );
}

/// "Öne çıkanlar": kısa, okunabilir içgörü satırları.
class IcgoruListesi extends StatelessWidget {
  const IcgoruListesi({super.key, required this.satirlar});

  final List<Icgoru> satirlar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    if (satirlar.isEmpty) {
      return const BosVeri('Bu süzgeçte veri bulunamadı.');
    }
    return Column(
      children: [
        for (final i in satirlar.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: i.renk.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(i.ikon, size: 15, color: i.renk),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(
                      _kalinli(
                        i.metin,
                        tema.textTheme.bodyMedium?.copyWith(height: 1.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class BosVeri extends StatelessWidget {
  const BosVeri(this.metin, {super.key});

  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Center(
      child: Text(
        metin,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class BarOge {
  const BarOge(this.ad, this.deger, {this.renk, this.no, this.ek});

  final String ad;
  final num deger;
  final Color? renk;
  final int? no;
  final String? ek;
}

/// Yatay çubuk listesi (ad · dolgu çubuğu · sayı ve yüzde). [tikla] verilirse satırlar dokunulabilir.
class BarListe extends StatelessWidget {
  const BarListe({
    super.key,
    required this.ogeler,
    this.toplam = 0,
    this.tikla,
    this.renk,
  });

  final List<BarOge> ogeler;
  final num toplam;
  final void Function(BarOge)? tikla;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    if (ogeler.isEmpty) return const BosVeri('Veri bulunamadı');
    final mx = ogeler.map((e) => e.deger).reduce(math.max);
    return Column(
      children: [
        for (var i = 0; i < ogeler.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: tikla == null || ogeler[i].no == null || ogeler[i].no! <= 0
                ? null
                : () => tikla!(ogeler[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ogeler[i].ad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        sayi(ogeler[i].deger),
                        style: tema.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (toplam > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '%${sayi(ogeler[i].deger * 100 / toplam, 1)}',
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      if (ogeler[i].ek != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            ogeler[i].ek!,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(
                          height: 7,
                          color: cs.onSurface.withValues(alpha: 0.07),
                        ),
                        FractionallySizedBox(
                          widthFactor: mx > 0
                              ? (ogeler[i].deger / mx).clamp(0, 1).toDouble()
                              : 0,
                          child: Container(
                            height: 7,
                            color:
                                ogeler[i].renk ??
                                renk ??
                                raporRenkleri[i % raporRenkleri.length],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Halka (donut) grafik + dokunulabilir gösterge listesi. Ortada toplam yazar.
class HalkaGrafik extends StatelessWidget {
  const HalkaGrafik({
    super.key,
    required this.ogeler,
    required this.birim,
    this.tikla,
  });

  final List<BarOge> ogeler;
  final String birim;
  final void Function(BarOge)? tikla;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final top = ogeler.fold<num>(0, (a, b) => a + b.deger);
    if (ogeler.isEmpty || top == 0) return const BosVeri('Veri yok');
    Color renk(int i) =>
        ogeler[i].renk ?? raporRenkleri[i % raporRenkleri.length];
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 54,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (e, r) {
                      final i = r?.touchedSection?.touchedSectionIndex ?? -1;
                      if (e is FlTapUpEvent && i >= 0 && tikla != null) {
                        tikla!(ogeler[i]);
                      }
                    },
                  ),
                  sections: [
                    for (var i = 0; i < ogeler.length; i++)
                      PieChartSectionData(
                        value: ogeler[i].deger.toDouble(),
                        color: renk(i),
                        radius: 22,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sayi(top),
                    style: tema.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    birim,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < ogeler.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: tikla == null || ogeler[i].no == null || ogeler[i].no! <= 0
                ? null
                : () => tikla!(ogeler[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: renk(i),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ogeler[i].ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    sayi(ogeler[i].deger),
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '%${sayi(ogeler[i].deger * 100 / top, 1)}',
                      textAlign: TextAlign.right,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _kovaEtiketi(String tur, String s) {
  final p = s.split('-');
  if (p.length < 3) return s;
  final ay = int.tryParse(p[1]) ?? 1;
  if (tur == 'yil') return p[0];
  if (tur == 'ay') return '${trAylarKisa[ay]} ${p[0].substring(2)}';
  return '${p[2]} ${trAylarKisa[ay]}';
}

/// Zaman serisi: çizgi ya da çubuk; önceki dönem kesik çizgiyle; isteğe bağlı ikinci seri (katılım gibi).
class TrendGrafik extends StatelessWidget {
  const TrendGrafik({
    super.key,
    required this.seri,
    required this.cubuk,
    required this.karsilastir,
    this.ad = 'Bu dönem',
    this.ek,
    this.ekAd = '',
  });

  final Map<String, dynamic> seri;
  final bool cubuk;
  final bool karsilastir;
  final String ad;
  final List<num>? ek;
  final String ekAd;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final tur = '${seri['tur']}';
    final etiket = [for (final e in (seri['etiket'] as List)) '$e'];
    final veri = [for (final e in (seri['veri'] as List)) sayiDeger(e)];
    final onceki = [
      for (final e in (seri['onceki'] as List? ?? const [])) sayiDeger(e),
    ];
    if (veri.isEmpty || veri.every((e) => e == 0)) {
      return const BosVeri('Bu dönemde kayıt yok');
    }
    final vurgu = cs.primary;
    final mx = [
      ...veri,
      if (karsilastir) ...onceki,
    ].reduce(math.max).toDouble();
    final aralik = math.max(1, (veri.length / 5).ceil());
    final govde = SizedBox(
      height: 220,
      child: cubuk
          ? BarChart(
              BarChartData(
                maxY: mx * 1.12,
                gridData: _izgara(cs),
                borderData: FlBorderData(show: false),
                titlesData: _basliklar(etiket, tur, aralik, cs),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                      '${_kovaEtiketi(tur, etiket[gi])}\n${sayi(r.toY)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < veri.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: veri[i].toDouble(),
                          color: vurgu,
                          width: veri.length > 40
                              ? 3
                              : (veri.length > 20 ? 6 : 10),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
              ),
            )
          : LineChart(
              LineChartData(
                minY: 0,
                maxY: mx * 1.12,
                gridData: _izgara(cs),
                borderData: FlBorderData(show: false),
                titlesData: _basliklar(etiket, tur, aralik, cs),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          s.barIndex == 0
                              ? '${_kovaEtiketi(tur, etiket[s.x.toInt()])}\n${sayi(s.y)}'
                              : 'Önceki: ${sayi(s.y)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < veri.length; i++)
                        FlSpot(i.toDouble(), veri[i].toDouble()),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: vurgu,
                    barWidth: 2.4,
                    dotData: FlDotData(show: veri.length <= 31),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          vurgu.withValues(alpha: 0.30),
                          vurgu.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  if (karsilastir && onceki.length > 1)
                    LineChartBarData(
                      spots: [
                        for (
                          var i = 0;
                          i < onceki.length && i < veri.length;
                          i++
                        )
                          FlSpot(i.toDouble(), onceki[i].toDouble()),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: const Color(0xFF9AA3B0),
                      barWidth: 1.8,
                      dashArray: [5, 4],
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          children: [
            _Gosterge(vurgu, ad, false),
            if (!cubuk && karsilastir && onceki.length > 1)
              const _Gosterge(Color(0xFF9AA3B0), 'Önceki dönem', true),
          ],
        ),
        const SizedBox(height: 8),
        govde,
        if (ek != null && ek!.any((e) => e > 0)) ...[
          const SizedBox(height: 14),
          _Gosterge(const Color(0xFF1D6FB8), ekAd, false),
          const SizedBox(height: 6),
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: _izgara(cs),
                borderData: FlBorderData(show: false),
                titlesData: _basliklar(etiket, tur, aralik, cs),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${_kovaEtiketi(tur, etiket[s.x.toInt()])}\n${sayi(s.y)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < ek!.length; i++)
                        FlSpot(i.toDouble(), ek![i].toDouble()),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: const Color(0xFF1D6FB8),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF1D6FB8).withValues(alpha: 0.10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  FlGridData _izgara(ColorScheme cs) => FlGridData(
    drawVerticalLine: false,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: cs.onSurface.withValues(alpha: 0.08), strokeWidth: 1),
  );

  FlTitlesData _basliklar(
    List<String> etiket,
    String tur,
    int aralik,
    ColorScheme cs,
  ) => FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 34,
        getTitlesWidget: (v, m) => v == m.max || v != v.roundToDouble()
            ? const SizedBox.shrink()
            : Text(
                sayi(v),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: aralik.toDouble(),
        getTitlesWidget: (v, m) {
          final i = v.toInt();
          if (i < 0 || i >= etiket.length || i % aralik != 0) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _kovaEtiketi(tur, etiket[i]),
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
          );
        },
      ),
    ),
  );
}

class _Gosterge extends StatelessWidget {
  const _Gosterge(this.renk, this.ad, this.kesik);

  final Color renk;
  final String ad;
  final bool kesik;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 16,
        height: kesik ? 2 : 4,
        decoration: BoxDecoration(
          color: renk,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(ad, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// Sütun grafik (haftanın günleri, saat dağılımı): en yüksek sütun vurgulanır.
class SutunGrafik extends StatelessWidget {
  const SutunGrafik({
    super.key,
    required this.etiketler,
    required this.degerler,
    this.yukseklik = 170,
  });

  final List<String> etiketler;
  final List<num> degerler;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mx = degerler.isEmpty ? 0 : degerler.reduce(math.max);
    if (mx == 0) return const BosVeri('Veri yok');
    return SizedBox(
      height: yukseklik,
      child: BarChart(
        BarChartData(
          maxY: mx * 1.15,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.onSurface.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, m) => v == m.max || v != v.roundToDouble()
                    ? const SizedBox.shrink()
                    : Text(
                        sayi(v),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, m) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    etiketler[v.toInt()],
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                sayi(r.toY),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < degerler.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: degerler[i].toDouble(),
                    width: degerler.length > 12 ? 9 : 22,
                    borderRadius: BorderRadius.circular(5),
                    color: degerler[i] == mx
                        ? cs.primary
                        : cs.primary.withValues(alpha: 0.28),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Yıl × ay ısı haritası (hücre koyuluğu adede göre).
class IsiHaritasi extends StatelessWidget {
  const IsiHaritasi({super.key, required this.isi});

  final Map<String, dynamic> isi;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final yillar = isi.keys.map(int.parse).toList()
      ..sort((a, b) => b.compareTo(a));
    if (yillar.isEmpty) return const BosVeri('Veri bulunamadı');
    num deger(int y, int m) {
      final s = isi['$y'];
      if (s is Map) return sayiDeger(s['$m']);
      return 0;
    }

    var mx = 1;
    for (final y in yillar) {
      for (var m = 1; m <= 12; m++) {
        mx = math.max(mx, deger(y, m).toInt());
      }
    }
    const hucre = 34.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 44),
              for (var m = 1; m <= 12; m++)
                SizedBox(
                  width: hucre,
                  child: Center(
                    child: Text(
                      trAylarKisa[m],
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: 52,
                child: Center(
                  child: Text(
                    'Toplam',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          for (final y in yillar)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$y',
                      style: tema.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (var m = 1; m <= 12; m++)
                    Builder(
                      builder: (_) {
                        final c = deger(y, m);
                        final a = c > 0
                            ? math.max(0.14, math.sqrt(c / mx))
                            : 0.0;
                        return Container(
                          width: hucre - 3,
                          height: 28,
                          margin: const EdgeInsets.only(right: 3),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c > 0
                                ? cs.primary.withValues(alpha: a)
                                : cs.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c > 0 ? sayi(c) : '',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: a > 0.55 ? Colors.white : cs.onSurface,
                            ),
                          ),
                        );
                      },
                    ),
                  SizedBox(
                    width: 52,
                    child: Center(
                      child: Text(
                        sayi(
                          List.generate(
                            12,
                            (i) => deger(y, i + 1),
                          ).fold<num>(0, (a, b) => a + b),
                        ),
                        style: tema.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Küçük tarih kutusu ("30 / Eki") + iki satırlı içerik (yaklaşan etkinlikler, en yüksek katılım…).
class TarihSatiri extends StatelessWidget {
  const TarihSatiri({
    super.key,
    required this.tarih,
    required this.baslik,
    this.alt = '',
    this.sag,
  });

  final String tarih;
  final String baslik;
  final String alt;
  final String? sag;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final p = tarih.length >= 10
        ? tarih.substring(0, 10).split('-')
        : ['', '', ''];
    final ay = int.tryParse(p[1]) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  p[2],
                  style: tema.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    height: 1.1,
                  ),
                ),
                Text(
                  ay > 0 ? trAylarKisa[ay] : '',
                  style: TextStyle(fontSize: 10, color: cs.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik.isEmpty ? '—' : baslik,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (alt.isNotEmpty)
                  Text(
                    alt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (sag != null)
            Text(
              sag!,
              style: tema.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

/// Etiket–değer satırı (yoğunluk özeti gibi).
class OzetSatiri extends StatelessWidget {
  const OzetSatiri(this.etiket, this.deger, {super.key});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(etiket, style: tema.textTheme.bodyMedium)),
          Text(
            deger,
            style: tema.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// İlerleme çubuğu (hedef, kayıt kalitesi).
class IlerlemeCubugu extends StatelessWidget {
  const IlerlemeCubugu({super.key, required this.oran, this.renk});

  final double oran;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          Container(height: 9, color: cs.onSurface.withValues(alpha: 0.08)),
          FractionallySizedBox(
            widthFactor: oran.clamp(0, 1).toDouble(),
            child: Container(height: 9, color: renk ?? cs.primary),
          ),
        ],
      ),
    );
  }
}

/// Grafik türü (çizgi / çubuk) gibi iki seçenekli küçük anahtar.
class MiniSecici extends StatelessWidget {
  const MiniSecici({
    super.key,
    required this.secenekler,
    required this.secili,
    required this.degisti,
  });

  final List<String> secenekler;
  final int secili;
  final ValueChanged<int> degisti;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < secenekler.length; i++)
            GestureDetector(
              onTap: () => degisti(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: i == secili ? cs.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  secenekler[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: i == secili ? FontWeight.w700 : FontWeight.w500,
                    color: i == secili ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// PHP boş diziyi `[]` olarak yazar; nesne beklenen yerlerde güvenli dönüşüm.
Map<String, dynamic> nesne(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
