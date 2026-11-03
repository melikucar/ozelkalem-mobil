import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../programlar/program_ortak.dart';
import 'rapor_harita.dart';
import 'rapor_ortak.dart';
import 'rapor_paneli.dart';

/// Talep istatistikleri (web "Talep İstatistikleri" paneli): KPI'lar, öne çıkanlar, aylık hedef, bekleyenler, yaklaşanlar,
/// trend, durum dağılımı, harita, kategoriler, bölge, haftanın günleri, ısı haritası, referans, yönetici, tekrar başvuranlar,
/// dönem değişimi ve kategori × durum tablosu. Grafiklere / satırlara dokunmak süzgeç uygular.
class TalepRaporu extends StatelessWidget {
  const TalepRaporu({super.key, required this.api, required this.referans});

  final ApiIstemci api;
  final Map<String, dynamic> referans;

  @override
  Widget build(BuildContext context) {
    final ref = (referans['talep'] as Map?)?.cast<String, dynamic>() ?? {};
    final iller = [
      for (final x in liste(ref['iller']))
        {'no': x['il_id'], 'adi': x['il_ad']},
    ];
    return RaporPaneli(
      api: api,
      tur: 'talep',
      secimler: (f) => [
        RaporSecimi(
          etiket: 'Kategori',
          ikon: Icons.category_outlined,
          liste: liste(ref['kategoriler']),
          deger: f.kat,
          degisti: (f, v) => f.kopya(kat: v),
        ),
        RaporSecimi(
          etiket: 'Durum',
          ikon: Icons.flag_outlined,
          liste: liste(ref['durumlar']),
          deger: f.durum,
          degisti: (f, v) => f.kopya(durum: v),
        ),
        RaporSecimi(
          etiket: 'İl',
          ikon: Icons.place_outlined,
          liste: iller,
          deger: f.il,
          degisti: (f, v) => f.kopya(il: v),
        ),
      ],
      icerik: (c, veri, f, uygula) => [
        _TalepGovde(
          api: api,
          veri: veri,
          f: f,
          uygula: uygula,
          durumlar: liste(ref['durumlar']),
        ),
      ],
    );
  }
}

class _TalepGovde extends StatefulWidget {
  const _TalepGovde({
    required this.api,
    required this.veri,
    required this.f,
    required this.uygula,
    required this.durumlar,
  });

  final ApiIstemci api;
  final Map<String, dynamic> veri;
  final RaporFiltre f;
  final void Function(RaporFiltre) uygula;
  final List<Map<String, dynamic>> durumlar;

  @override
  State<_TalepGovde> createState() => _TalepGovdeState();
}

class _TalepGovdeState extends State<_TalepGovde> {
  int _trend = 0; // 0 çizgi, 1 çubuk
  int _bolge = 0; // 0 ilçe, 1 il
  final _hedef = TextEditingController();
  bool _hedefKayit = false;

  Map<String, dynamic> get v => widget.veri;
  Map<String, dynamic> get kpi => Map<String, dynamic>.from(v['kpi'] as Map);
  bool get karsi =>
      widget.f.karsilastir && (v['aralik'] as Map)['onceki'] != null;

  int get _hedefDegeri => sayiDeger((v['hedef'] as Map?)?['hedef']).toInt();

  @override
  void initState() {
    super.initState();
    _hedef.text = _hedefDegeri > 0 ? '$_hedefDegeri' : '';
  }

  @override
  void didUpdateWidget(_TalepGovde eski) {
    super.didUpdateWidget(eski);
    if (eski.veri != widget.veri) {
      _hedef.text = _hedefDegeri > 0 ? '$_hedefDegeri' : '';
    }
  }

  @override
  void dispose() {
    _hedef.dispose();
    super.dispose();
  }

  Widget _kutu(String baslik, IconData ikon, Widget cocuk, {Widget? sag}) =>
      ProgramKutu(baslik: baslik, ikon: ikon, cocuk: cocuk, sag: sag);

  Future<void> _hedefKaydet() async {
    final h = int.tryParse(_hedef.text.trim()) ?? 0;
    setState(() => _hedefKayit = true);
    try {
      await widget.api.post('raporlar/talep-hedef', govde: {'hedef': h});
      widget.uygula(widget.f);
    } on ApiHata catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                e.agHatasi
                    ? 'Hedef için internet bağlantısı gerekir.'
                    : e.mesaj,
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _hedefKayit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final k = kpi;
    final toplam = sayiDeger(k['toplam']);
    final onceki = karsi ? sayiDeger(k['onceki']) : null;
    final kat = liste(v['kategori']);
    final durum = liste(v['durum']);
    final seri = Map<String, dynamic>.from(v['seri'] as Map);
    final hafta = [for (final e in (v['hafta'] as List)) sayiDeger(e)];
    final yogun = k['yogun'] as Map?;
    final tekil = sayiDeger(k['tekil']);
    final olumluOran = k['olumlu_oran'];

    final icgoru = <Icgoru>[];
    if (karsi && sayiDeger(k['onceki']) > 0) {
      final y =
          (toplam - sayiDeger(k['onceki'])) * 100 / sayiDeger(k['onceki']);
      icgoru.add(
        Icgoru(
          y >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          y >= 0 ? const Color(0xFF1F8A5B) : const Color(0xFFB3202F),
          'Talep sayısı önceki döneme göre **%${sayi(y.abs(), 1)}${y >= 0 ? ' arttı' : ' azaldı'}** (${sayi(k['onceki'])} → ${sayi(toplam)}).',
        ),
      );
    }
    if (kat.isNotEmpty && toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.layers_outlined,
          const Color(0xFFB71C2B),
          'En yoğun kategori **${kat.first['ad']}**: ${sayi(kat.first['c'])} talep (%${sayi(sayiDeger(kat.first['c']) * 100 / toplam, 1)}).',
        ),
      );
    }
    final artan =
        kat
            .where(
              (c) =>
                  sayiDeger(c['onceki']) > 0 &&
                  sayiDeger(c['c']) > sayiDeger(c['onceki']),
            )
            .toList()
          ..sort(
            (a, b) => (sayiDeger(b['c']) - sayiDeger(b['onceki'])).compareTo(
              sayiDeger(a['c']) - sayiDeger(a['onceki']),
            ),
          );
    if (karsi && artan.isNotEmpty) {
      icgoru.add(
        Icgoru(
          Icons.local_fire_department_outlined,
          const Color(0xFFC77D0A),
          '**${artan.first['ad']}** kategorisi en çok artan: ${sayi(artan.first['onceki'])} → ${sayi(artan.first['c'])}.',
        ),
      );
    }
    final hm = hafta.isEmpty ? 0 : hafta.reduce(math.max);
    if (hm > 0 && toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.calendar_view_week_rounded,
          const Color(0xFF1D6FB8),
          'Haftanın en yoğun günü **${raporGunlerUzun[hafta.indexOf(hm)]}** (%${sayi(hm * 100 / toplam, 1)}).',
        ),
      );
    }
    if (yogun != null) {
      icgoru.add(
        Icgoru(
          Icons.bolt_rounded,
          const Color(0xFF7B4FB3),
          'En yoğun gün **${tarihTr(yogun['gun'])}**: ${sayi(yogun['c'])} talep.',
        ),
      );
    }
    if (olumluOran != null) {
      icgoru.add(
        Icgoru(
          Icons.check_circle_outline_rounded,
          const Color(0xFF1F8A5B),
          'Sonuçlanan taleplerin **%${sayi(olumluOran, 1)}**\'i olumlu.',
        ),
      );
    }
    if (toplam > 0 && sayiDeger(k['bekleyen']) * 100 / toplam >= 10) {
      icgoru.add(
        Icgoru(
          Icons.hourglass_bottom_rounded,
          const Color(0xFFC77D0A),
          '**${sayi(k['bekleyen'])}** talep hâlâ beklemede (%${sayi(sayiDeger(k['bekleyen']) * 100 / toplam, 1)}).',
        ),
      );
    }
    final refs = liste(v['referans']);
    if (refs.isNotEmpty && toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.group_outlined,
          const Color(0xFF0F8B9C),
          'En çok referans: **${refs.first['ad']}** (${sayi(refs.first['c'])} talep).',
        ),
      );
    }

    final gunluk = sayiDeger(k['gunluk']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiIzgarasi(
          kartlar: [
            KpiVeri(
              ad: 'Toplam talep',
              ikon: Icons.inbox_outlined,
              renk: const Color(0xFFB71C2B),
              deger: sayi(toplam),
              delta: onceki == null
                  ? null
                  : DeltaRozet(simdi: toplam, once: onceki),
              alt: karsi ? 'Önceki: ${sayi(k['onceki'])}' : '',
              spark: [for (final e in (seri['veri'] as List)) sayiDeger(e)],
            ),
            KpiVeri(
              ad: 'Günlük ortalama',
              ikon: Icons.speed_rounded,
              renk: const Color(0xFF1D6FB8),
              deger: sayi(gunluk, 2),
              delta: karsi && k['gunluk_onceki'] != null
                  ? DeltaRozet(
                      simdi: gunluk,
                      once: sayiDeger(k['gunluk_onceki']),
                    )
                  : null,
              alt: yogun != null
                  ? 'En yoğun: ${tarihTr(yogun['gun'], kisa: true)} (${yogun['c']})'
                  : '',
            ),
            KpiVeri(
              ad: 'Tekil başvuran',
              ikon: Icons.people_alt_outlined,
              renk: const Color(0xFF7B4FB3),
              deger: sayi(tekil),
              delta: karsi
                  ? DeltaRozet(simdi: tekil, once: sayiDeger(k['tekil_onceki']))
                  : null,
              alt: 'Kişi başı ${sayi(tekil > 0 ? toplam / tekil : 0, 2)} talep',
            ),
            KpiVeri(
              ad: 'Olumlu sonuç',
              ikon: Icons.check_circle_outline_rounded,
              renk: const Color(0xFF1F8A5B),
              deger: olumluOran == null ? '—' : '%${sayi(olumluOran, 1)}',
              alt:
                  '${sayi(k['olumlu'])} olumlu · ${sayi(k['olumsuz'])} olumsuz',
            ),
            KpiVeri(
              ad: 'Bekleyen',
              ikon: Icons.hourglass_bottom_rounded,
              renk: const Color(0xFFC77D0A),
              deger: sayi(k['bekleyen']),
              alt: toplam > 0
                  ? '%${sayi(sayiDeger(k['bekleyen']) * 100 / toplam, 1)} oranında'
                  : '',
            ),
            KpiVeri(
              ad: 'Mülakat / randevu',
              ikon: Icons.event_available_outlined,
              renk: const Color(0xFF0F8B9C),
              deger: sayi(k['mulakat']),
              alt: toplam > 0
                  ? '%${sayi(sayiDeger(k['mulakat']) * 100 / toplam, 1)} oranında'
                  : '',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _kutu(
          'Öne çıkanlar',
          Icons.auto_awesome_outlined,
          IcgoruListesi(satirlar: icgoru),
        ),
        _kutu(
          'Harita · bölge ısı haritası',
          Icons.public_rounded,
          RaporHaritasi(
            veri: nesne(v['harita']),
            birim: 'talep',
            ilSec: (id) => widget.uygula(widget.f.kopya(il: id)),
            ilTemizle: () => widget.uygula(widget.f.kopya(il: 0)),
          ),
        ),
        _kutu(
          'Yaklaşan 14 gün',
          Icons.notifications_active_outlined,
          _yaklasanKutusu(tema, cs),
        ),
        _kutu(
          'Talep trendi',
          Icons.show_chart_rounded,
          TrendGrafik(
            seri: seri,
            cubuk: _trend == 1,
            karsilastir: karsi,
            ad: 'Talep',
          ),
          sag: MiniSecici(
            secenekler: const ['Çizgi', 'Çubuk'],
            secili: _trend,
            degisti: (i) => setState(() => _trend = i),
          ),
        ),
        _kutu(
          'Durum dağılımı',
          Icons.donut_large_rounded,
          HalkaGrafik(
            ogeler: [
              for (var i = 0; i < durum.length; i++)
                BarOge(
                  '${durum[i]['ad']}',
                  sayiDeger(durum[i]['c']),
                  no: sayiDeger(durum[i]['no']).toInt(),
                  renk: durumRengi('${durum[i]['ad']}', i),
                ),
            ],
            birim: 'talep',
            tikla: (o) => widget.uygula(widget.f.kopya(durum: o.no)),
          ),
        ),
        _kutu(
          'Kategoriler',
          Icons.layers_outlined,
          _kategoriKutusu(kat, toplam),
        ),
        _kutu(
          'Bölge dağılımı',
          Icons.place_outlined,
          BarListe(
            ogeler: _bolge == 0
                ? [
                    for (final x in liste(v['ilce']))
                      BarOge(
                        '${x['ilce']}${'${x['il']}'.isNotEmpty ? ' / ${x['il']}' : ''}',
                        sayiDeger(x['c']),
                      ),
                  ]
                : [
                    for (final x in liste(v['il']))
                      BarOge('${x['il']}', sayiDeger(x['c'])),
                  ],
            toplam: toplam,
            renk: const Color(0xFF1D6FB8),
          ),
          sag: MiniSecici(
            secenekler: const ['İlçe', 'İl'],
            secili: _bolge,
            degisti: (i) => setState(() => _bolge = i),
          ),
        ),
        _kutu(
          'Haftanın günlerine göre',
          Icons.calendar_view_week_rounded,
          SutunGrafik(etiketler: raporGunler, degerler: hafta),
        ),
        _kutu(
          'Yıl / ay ısı haritası',
          Icons.grid_view_rounded,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tarih süzgecinden bağımsızdır.',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              IsiHaritasi(isi: nesne(v['isi'])),
            ],
          ),
        ),
        _kutu(
          'En çok referans olanlar',
          Icons.group_outlined,
          BarListe(
            ogeler: [
              for (final x in refs) BarOge('${x['ad']}', sayiDeger(x['c'])),
            ],
            renk: const Color(0xFF0F8B9C),
          ),
        ),
        _kutu(
          'Talepleri giren yönetici',
          Icons.edit_note_rounded,
          BarListe(
            ogeler: [
              for (final x in liste(v['yonetici']))
                BarOge('${x['ad']}', sayiDeger(x['c'])),
            ],
            toplam: toplam,
            renk: const Color(0xFF7B4FB3),
          ),
        ),
        _kutu(
          'Bekleyen talepler · yaş dağılımı',
          Icons.hourglass_empty_rounded,
          _bekleyenKutusu(tema, cs),
        ),
        _kutu(
          'Tekrar başvuranlar',
          Icons.repeat_rounded,
          _tekrarKutusu(tema, cs),
        ),
        _kutu(
          'Dönem değişimi (kategori)',
          Icons.trending_up_rounded,
          _degisimKutusu(kat, tema, cs),
        ),
        _kutu(
          'Kategori × durum tablosu',
          Icons.table_chart_outlined,
          _caprazKutusu(kat, durum, tema, cs),
        ),
        _kutu(
          'Aylık hedef',
          Icons.flag_circle_outlined,
          _hedefKutusu(tema, cs),
        ),
      ],
    );
  }

  Widget _kategoriKutusu(List<Map<String, dynamic>> kat, num toplam) {
    final l = kat.take(10).toList();
    final digerleri = kat
        .skip(10)
        .fold<num>(0, (a, b) => a + sayiDeger(b['c']));
    return BarListe(
      ogeler: [
        for (final x in l)
          BarOge(
            '${x['ad']}',
            sayiDeger(x['c']),
            no: sayiDeger(x['no']).toInt(),
          ),
        if (digerleri > 0)
          BarOge('Diğer (${kat.length - 10} kategori)', digerleri),
      ],
      toplam: toplam,
      tikla: (o) => widget.uygula(widget.f.kopya(kat: o.no)),
    );
  }

  Widget _hedefKutusu(ThemeData tema, ColorScheme cs) {
    final t = Map<String, dynamic>.from(v['hedef'] as Map);
    final hedef = sayiDeger(t['hedef']);
    final buAy = sayiDeger(t['bu_ay']);
    final gun = sayiDeger(t['gun']);
    final ayGun = sayiDeger(t['ay_gun']);
    final tah = gun > 0 ? (buAy / gun * ayGun).round() : 0;
    final y = hedef > 0 ? math.min(100, buAy * 100 / hedef).toDouble() : 0.0;
    final tamam = hedef > 0 && buAy >= hedef;
    final rozet = tamam ? const Color(0xFF1F8A5B) : const Color(0xFFC77D0A);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              sayi(buAy),
              style: tema.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            if (hedef > 0)
              Text(
                ' / ${sayi(hedef)}',
                style: tema.textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            const Spacer(),
            if (hedef > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rozet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tamam ? 'Hedefe ulaşıldı' : '%${sayi(y)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: rozet,
                  ),
                ),
              ),
          ],
        ),
        if (hedef > 0) ...[
          const SizedBox(height: 10),
          IlerlemeCubugu(oran: y / 100),
        ],
        const SizedBox(height: 8),
        Text(
          hedef > 0
              ? 'Ay sonu tahmini ${sayi(tah)} · geçen ay ${sayi(t['gecen_ay'])} · ${sayi(ayGun - gun)} gün kaldı'
              : 'Bu ay ${sayi(buAy)} · geçen ay ${sayi(t['gecen_ay'])} · tahmini ay sonu ${sayi(tah)}. Aylık talep hedefi belirleyerek ilerlemeyi izleyin.',
          style: tema.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hedef,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Aylık hedef',
                  prefixIcon: Icon(Icons.flag_outlined),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _hedefKayit ? null : _hedefKaydet,
              child: Text(hedef > 0 ? 'Güncelle' : 'Hedef koy'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bekleyenKutusu(ThemeData tema, ColorScheme cs) {
    final t = Map<String, dynamic>.from(v['takip'] as Map);
    final bek = sayiDeger(t['bekleyen']);
    if (bek == 0) return const BosVeri('Bekleyen talep yok');
    const adlar = ['0-7 gün', '8-30 gün', '31-90 gün', '90+ gün'];
    const renkler = [
      Color(0xFF1F8A5B),
      Color(0xFFE0A100),
      Color(0xFFC77D0A),
      Color(0xFFB3202F),
    ];
    final yas = [for (final e in (t['yas'] as List)) sayiDeger(e)];
    final tp = math.max(1, yas.fold<num>(0, (a, b) => a + b));
    final enEski = t['en_eski'] as String?;
    var gecen = 0;
    if (enEski != null && enEski.length >= 10) {
      gecen = DateTime.now()
          .difference(DateTime.parse(enEski.substring(0, 10)))
          .inDays;
    }
    final bekleyenDurum = widget.durumlar
        .where((d) => '${d['adi']}'.toLowerCase() == 'beklemede')
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              sayi(bek),
              style: tema.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'talep işlem bekliyor${enEski != null ? '\nen eskisi ${tarihTr(enEski)} (${gecen > 400 ? '${sayi(gecen / 365, 1)} yıl' : '$gecen gün'})' : ''}',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < yas.length; i++)
                  if (yas[i] > 0)
                    Expanded(
                      flex: math.max(1, (yas[i] * 1000 / tp).round()),
                      child: Container(color: renkler[i]),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < yas.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: renkler[i],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(adlar[i])),
                Text(
                  sayi(yas[i]),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    '%${sayi(yas[i] * 100 / tp)}',
                    textAlign: TextAlign.right,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (bekleyenDurum != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => widget.uygula(
                widget.f.kopya(
                  durum: (bekleyenDurum['no'] as num).toInt(),
                  donem: 'tumu',
                ),
              ),
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Bekleyenleri süz'),
            ),
          ),
      ],
    );
  }

  Widget _yaklasanKutusu(ThemeData tema, ColorScheme cs) {
    final t = Map<String, dynamic>.from(v['takip'] as Map);
    final mulakat = liste(t['mulakat']);
    final hat = liste(t['hatirlatici']);
    final geciken = sayiDeger(t['geciken_hatirlatici']);
    Widget baslik(String m) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        m,
        style: tema.textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        baslik('Mülakat / randevu'),
        if (mulakat.isEmpty)
          const BosVeri('Önümüzdeki 14 günde mülakat yok.')
        else
          for (final m in mulakat)
            TarihSatiri(
              tarih: '${m['tarih']}',
              baslik: '${m['ad']}',
              alt: '${m['yer'] ?? ''}',
            ),
        baslik('Hatırlatıcılar'),
        if (hat.isEmpty)
          const BosVeri('Önümüzdeki 14 günde hatırlatıcı yok.')
        else
          for (final m in hat)
            TarihSatiri(tarih: '${m['tarih']}', baslik: '${m['ad']}'),
        if (geciken > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFD6293A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${sayi(geciken)} gecikmiş hatırlatıcı',
                style: const TextStyle(
                  color: Color(0xFFD6293A),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tekrarKutusu(ThemeData tema, ColorScheme cs) {
    final l = liste(v['tekrar']);
    if (l.isEmpty) return const BosVeri('Tekrar başvuran yok');
    return Column(
      children: [
        for (var i = 0; i < l.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${l[i]['ad']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${sayi(l[i]['c'])} talep',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    'son ${tarihTr(l[i]['son'], kisa: true)}',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _degisimKutusu(
    List<Map<String, dynamic>> kat,
    ThemeData tema,
    ColorScheme cs,
  ) {
    if (!karsi) {
      return const BosVeri('Karşılaştırma kapalı ya da "Tümü" seçili');
    }
    final l =
        [
          for (final c in kat)
            if (sayiDeger(c['onceki']) > 0 || sayiDeger(c['c']) > 0) c,
        ]..sort(
          (a, b) => (sayiDeger(b['c']) - sayiDeger(b['onceki']))
              .abs()
              .compareTo((sayiDeger(a['c']) - sayiDeger(a['onceki'])).abs()),
        );
    if (l.isEmpty) return const BosVeri('Veri yok');
    return Column(
      children: [
        for (final c in l.take(7))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${c['ad']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${sayi(c['onceki'])} → ${sayi(c['c'])}',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                DeltaRozet(
                  simdi: sayiDeger(c['c']),
                  once: sayiDeger(c['onceki']),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _caprazKutusu(
    List<Map<String, dynamic>> kat,
    List<Map<String, dynamic>> durum,
    ThemeData tema,
    ColorScheme cs,
  ) {
    final ilk = kat.take(8).toList();
    if (ilk.isEmpty) return const BosVeri('Veri bulunamadı');
    final capraz = nesne(v['capraz']);
    Map<String, dynamic> satir(Map<String, dynamic> k) =>
        (capraz['${k['no']}'] as Map?)?.cast<String, dynamic>() ?? {};
    final dtop = <String, num>{};
    for (final k in ilk) {
      satir(k).forEach((d, c) => dtop[d] = (dtop[d] ?? 0) + sayiDeger(c));
    }
    final dlar = dtop.keys.toList()
      ..sort((a, b) => dtop[b]!.compareTo(dtop[a]!));
    final dad = {for (final d in durum) '${d['no']}': '${d['ad']}'};
    const ilkSut = 112.0;
    const sut = 62.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: ilkSut),
              for (var i = 0; i < dlar.length; i++)
                SizedBox(
                  width: sut,
                  child: Text(
                    dad[dlar[i]] ?? 'Belirsiz',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: durumRengi(dad[dlar[i]] ?? '', i),
                    ),
                  ),
                ),
              const SizedBox(
                width: sut,
                child: Text(
                  'Toplam',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(
                width: sut,
                child: Text(
                  'Olumlu %',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          for (final k in ilk)
            Builder(
              builder: (_) {
                final s = satir(k);
                num tp = 0;
                num olumlu = 0;
                num olumsuz = 0;
                for (final d in dlar) {
                  final c = sayiDeger(s[d]);
                  tp += c;
                  if ((dad[d] ?? '').toLowerCase() == 'olumlu') olumlu += c;
                  if ((dad[d] ?? '').toLowerCase() == 'olumsuz') olumsuz += c;
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: ilkSut,
                        child: Text(
                          '${k['ad']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (var i = 0; i < dlar.length; i++)
                        Builder(
                          builder: (_) {
                            final c = sayiDeger(s[dlar[i]]);
                            final a = c > 0
                                ? math.max(0.12, math.sqrt(c / dtop[dlar[i]]!))
                                : 0.0;
                            final r = durumRengi(dad[dlar[i]] ?? '', i);
                            return Container(
                              width: sut - 4,
                              height: 28,
                              margin: const EdgeInsets.only(right: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c > 0
                                    ? r.withValues(alpha: a)
                                    : cs.onSurface.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                c > 0 ? sayi(c) : '·',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: a > 0.55 ? Colors.white : cs.onSurface,
                                ),
                              ),
                            );
                          },
                        ),
                      SizedBox(
                        width: sut,
                        child: Center(
                          child: Text(
                            sayi(tp),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: sut,
                        child: Center(
                          child: Text(
                            (olumlu + olumsuz) > 0
                                ? '%${sayi(olumlu * 100 / (olumlu + olumsuz))}'
                                : '—',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: (olumlu + olumsuz) > 0
                                  ? const Color(0xFF1F8A5B)
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
