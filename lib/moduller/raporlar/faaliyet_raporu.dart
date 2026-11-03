import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../programlar/program_ortak.dart';
import 'rapor_harita.dart';
import 'rapor_ortak.dart';
import 'rapor_paneli.dart';

/// Faaliyet istatistikleri (web "Faaliyet İstatistikleri" paneli): KPI'lar, öne çıkanlar, faaliyet ve katılım trendi,
/// kategori dağılımı, yer haritası, yerler, haftanın günleri, kategoriye göre katılım, ısı haritası, en yüksek katılımlılar,
/// giren yönetici, kayıt kalitesi ve yoğunluk özeti.
class FaaliyetRaporu extends StatelessWidget {
  const FaaliyetRaporu({super.key, required this.api, required this.referans});

  final ApiIstemci api;
  final Map<String, dynamic> referans;

  @override
  Widget build(BuildContext context) {
    final ref = (referans['faaliyet'] as Map?)?.cast<String, dynamic>() ?? {};
    return RaporPaneli(
      api: api,
      tur: 'faaliyet',
      secimler: (f) => [
        RaporSecimi(
          etiket: 'Kategori',
          ikon: Icons.category_outlined,
          liste: liste(ref['kategoriler']),
          deger: f.kat,
          degisti: (f, v) => f.kopya(kat: v),
        ),
        RaporSecimi(
          etiket: 'Yer',
          ikon: Icons.place_outlined,
          liste: liste(ref['yerler']),
          deger: f.yer,
          degisti: (f, v) => f.kopya(yer: v),
        ),
      ],
      icerik: (c, veri, f, uygula) => [
        _FaaliyetGovde(veri: veri, f: f, uygula: uygula),
      ],
    );
  }
}

class _FaaliyetGovde extends StatefulWidget {
  const _FaaliyetGovde({
    required this.veri,
    required this.f,
    required this.uygula,
  });

  final Map<String, dynamic> veri;
  final RaporFiltre f;
  final void Function(RaporFiltre) uygula;

  @override
  State<_FaaliyetGovde> createState() => _FaaliyetGovdeState();
}

class _FaaliyetGovdeState extends State<_FaaliyetGovde> {
  int _trend = 0;

  Map<String, dynamic> get v => widget.veri;

  Widget _kutu(String baslik, IconData ikon, Widget cocuk, {Widget? sag}) =>
      ProgramKutu(baslik: baslik, ikon: ikon, cocuk: cocuk, sag: sag);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final k = Map<String, dynamic>.from(v['kpi'] as Map);
    final karsi =
        widget.f.karsilastir && (v['aralik'] as Map)['onceki'] != null;
    final toplam = sayiDeger(k['toplam']);
    final seri = Map<String, dynamic>.from(v['seri'] as Map);
    final kat = liste(v['kategori']);
    final yer = liste(v['yer']);
    final hafta = [for (final e in (v['hafta'] as List)) sayiDeger(e)];
    final enKatilim = liste(v['en_katilim']);
    final yogun = k['yogun'] as Map?;
    final gun = sayiDeger((v['aralik'] as Map)['gun']);
    final seriVeri = [for (final e in (seri['veri'] as List)) sayiDeger(e)];
    final katilimSeri = [
      for (final e in (seri['katilim'] as List)) sayiDeger(e),
    ];

    final icgoru = <Icgoru>[];
    if (karsi && sayiDeger(k['onceki']) > 0) {
      final y =
          (toplam - sayiDeger(k['onceki'])) * 100 / sayiDeger(k['onceki']);
      icgoru.add(
        Icgoru(
          y >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          y >= 0 ? const Color(0xFF1F8A5B) : const Color(0xFFB3202F),
          'Faaliyet sayısı önceki döneme göre **%${sayi(y.abs(), 1)}${y >= 0 ? ' arttı' : ' azaldı'}** (${sayi(k['onceki'])} → ${sayi(toplam)}).',
        ),
      );
    }
    if (kat.isNotEmpty && toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.layers_outlined,
          const Color(0xFFB71C2B),
          'En çok **${kat.first['ad']}** yapılmış: ${sayi(kat.first['c'])} (%${sayi(sayiDeger(kat.first['c']) * 100 / toplam, 1)}).',
        ),
      );
    }
    final hm = hafta.isEmpty ? 0 : hafta.reduce((a, b) => a > b ? a : b);
    if (hm > 0 && toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.calendar_view_week_rounded,
          const Color(0xFF1D6FB8),
          'Haftanın en yoğun günü **${raporGunlerUzun[hafta.indexOf(hm)]}** (%${sayi(hm * 100 / toplam, 1)}).',
        ),
      );
    }
    if (yer.isNotEmpty) {
      icgoru.add(
        Icgoru(
          Icons.place_outlined,
          const Color(0xFF0F8B9C),
          'En sık yer **${yer.first['ad']}**: ${sayi(yer.first['c'])} faaliyet.',
        ),
      );
    }
    if (toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.image_outlined,
          const Color(0xFFC77D0A),
          'Faaliyetlerin **%${sayi(sayiDeger(k['fotografli']) * 100 / toplam)}** oranında faaliyette fotoğraf var.',
        ),
      );
    }
    if (enKatilim.isNotEmpty) {
      icgoru.add(
        Icgoru(
          Icons.emoji_events_outlined,
          const Color(0xFF7B4FB3),
          'En yüksek katılım **${sayi(enKatilim.first['katilim'])}** kişi (${('${enKatilim.first['ad']}').isEmpty ? 'adsız' : enKatilim.first['ad']}).',
        ),
      );
    }

    final dolu = seriVeri.where((c) => c > 0).length;
    final haftaIci = hafta.length >= 5
        ? hafta.take(5).fold<num>(0, (a, b) => a + b)
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiIzgarasi(
          kartlar: [
            KpiVeri(
              ad: 'Toplam faaliyet',
              ikon: Icons.folder_open_rounded,
              renk: const Color(0xFFB71C2B),
              deger: sayi(toplam),
              delta: karsi
                  ? DeltaRozet(simdi: toplam, once: sayiDeger(k['onceki']))
                  : null,
              alt: karsi ? 'Önceki: ${sayi(k['onceki'])}' : '',
              spark: seriVeri,
            ),
            KpiVeri(
              ad: 'Toplam katılım',
              ikon: Icons.groups_2_outlined,
              renk: const Color(0xFF1D6FB8),
              deger: sayi(k['katilim']),
              delta: karsi
                  ? DeltaRozet(
                      simdi: sayiDeger(k['katilim']),
                      once: sayiDeger(k['katilim_onceki']),
                    )
                  : null,
              alt: karsi ? 'Önceki: ${sayi(k['katilim_onceki'])}' : '',
              spark: katilimSeri,
            ),
            KpiVeri(
              ad: 'Ortalama katılım',
              ikon: Icons.speed_rounded,
              renk: const Color(0xFF7B4FB3),
              deger: sayi(k['ortalama'], 1),
              alt: 'En yüksek: ${sayi(k['max_katilim'])}',
            ),
            KpiVeri(
              ad: 'Fotoğraflı',
              ikon: Icons.image_outlined,
              renk: const Color(0xFFC77D0A),
              deger: toplam > 0
                  ? '%${sayi(sayiDeger(k['fotografli']) * 100 / toplam)}'
                  : '—',
              alt: '${sayi(k['fotografli'])} faaliyette',
            ),
            KpiVeri(
              ad: 'Haber bağlantılı',
              ikon: Icons.newspaper_rounded,
              renk: const Color(0xFF0F8B9C),
              deger: toplam > 0
                  ? '%${sayi(sayiDeger(k['haberli']) * 100 / toplam)}'
                  : '—',
              alt: '${sayi(k['haberli'])} faaliyette',
            ),
            KpiVeri(
              ad: 'Farklı yer',
              ikon: Icons.place_outlined,
              renk: const Color(0xFF1F8A5B),
              deger: sayi(k['yer_sayi']),
              alt: yogun != null
                  ? 'En yoğun: ${tarihTr(yogun['gun'], kisa: true)} (${yogun['c']})'
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
          'Faaliyet ve katılım trendi',
          Icons.show_chart_rounded,
          TrendGrafik(
            seri: seri,
            cubuk: _trend == 1,
            karsilastir: karsi,
            ad: 'Faaliyet',
            ek: katilimSeri,
            ekAd: 'Katılım',
          ),
          sag: MiniSecici(
            secenekler: const ['Çizgi', 'Çubuk'],
            secili: _trend,
            degisti: (i) => setState(() => _trend = i),
          ),
        ),
        _kutu(
          'Kategori dağılımı',
          Icons.donut_large_rounded,
          HalkaGrafik(
            ogeler: [
              for (final c in kat)
                BarOge(
                  '${c['ad']}',
                  sayiDeger(c['c']),
                  no: sayiDeger(c['no']).toInt(),
                ),
            ],
            birim: 'faaliyet',
            tikla: (o) => widget.uygula(widget.f.kopya(kat: o.no)),
          ),
        ),
        _kutu(
          'Harita · faaliyetlerin yer dağılımı',
          Icons.public_rounded,
          RaporHaritasi(
            veri: nesne(v['harita']),
            birim: 'faaliyet',
            ilSec: (id) => widget.uygula(widget.f.kopya(il: id)),
            ilTemizle: () => widget.uygula(widget.f.kopya(il: 0)),
          ),
        ),
        _kutu(
          'Yerler',
          Icons.place_outlined,
          BarListe(
            ogeler: [
              for (final y in yer)
                BarOge(
                  '${y['ad']}',
                  sayiDeger(y['c']),
                  no: sayiDeger(y['no']).toInt(),
                ),
            ],
            toplam: toplam,
            renk: const Color(0xFF0F8B9C),
            tikla: (o) => widget.uygula(widget.f.kopya(yer: o.no)),
          ),
        ),
        _kutu(
          'Haftanın günlerine göre',
          Icons.calendar_view_week_rounded,
          SutunGrafik(etiketler: raporGunler, degerler: hafta),
        ),
        _kutu(
          'Kategoriye göre katılım',
          Icons.groups_2_outlined,
          BarListe(
            ogeler: [
              for (final c
                  in (kat.where((c) => sayiDeger(c['katilim']) > 0).toList()
                    ..sort(
                      (a, b) =>
                          sayiDeger(b['katilim'])
                              .compareTo(sayiDeger(a['katilim'])),
                    )))
                BarOge('${c['ad']}', sayiDeger(c['katilim'])),
            ],
          ),
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
          'En yüksek katılımlı faaliyetler',
          Icons.emoji_events_outlined,
          enKatilim.isEmpty
              ? const BosVeri('Katılım bilgisi girilmiş faaliyet yok')
              : Column(
                  children: [
                    for (final m in enKatilim)
                      TarihSatiri(
                        tarih: '${m['tarih']}',
                        baslik: ('${m['ad']}').isEmpty
                            ? 'Adsız faaliyet'
                            : '${m['ad']}',
                        alt: '${m['kategori']}',
                        sag: sayi(m['katilim']),
                      ),
                  ],
                ),
        ),
        _kutu(
          'Faaliyeti giren yönetici',
          Icons.edit_note_rounded,
          BarListe(
            ogeler: [
              for (final x in liste(v['ekleyen']))
                BarOge('${x['ad']}', sayiDeger(x['c'])),
            ],
            toplam: toplam,
            renk: const Color(0xFF7B4FB3),
          ),
        ),
        _kutu(
          'Kayıt kalitesi',
          Icons.high_quality_outlined,
          toplam == 0
              ? const BosVeri('Veri yok')
              : Column(
                  children: [
                    for (final x in [
                      (
                        'Fotoğraflı faaliyet',
                        sayiDeger(k['fotografli']),
                        const Color(0xFFC77D0A),
                      ),
                      (
                        'Haber bağlantılı faaliyet',
                        sayiDeger(k['haberli']),
                        const Color(0xFF0F8B9C),
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(x.$1)),
                                Text(
                                  '${sayi(x.$2)} / ${sayi(toplam)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            IlerlemeCubugu(oran: x.$2 / toplam, renk: x.$3),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        _kutu(
          'Yoğunluk özeti',
          Icons.speed_rounded,
          Column(
            children: [
              OzetSatiri(
                'Faaliyet olan gün/hafta/ay',
                '$dolu / ${seriVeri.length}',
              ),
              OzetSatiri('Dönem uzunluğu', '${sayi(gun)} gün'),
              OzetSatiri(
                'Günlük ortalama',
                sayi(toplam / (gun < 1 ? 1 : gun), 2),
              ),
              OzetSatiri(
                'Hafta içi payı',
                '%${sayi(toplam > 0 ? haftaIci * 100 / toplam : 0)}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
