import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../programlar/program_ortak.dart';
import 'rapor_harita.dart';
import 'rapor_ortak.dart';
import 'rapor_paneli.dart';

/// Ajanda istatistikleri (web "Ajanda İstatistikleri" paneli): KPI'lar, öne çıkanlar, bugün / bu hafta, yaklaşan programlar,
/// randevu durumları, program trendi, haftanın günleri, yer haritası, saat dağılımı, mekânlar, ünvan / kurum, ısı haritası,
/// randevu kategorileri, giren yönetici, tekrarlayan programlar ve yoğunluk özeti.
class AjandaRaporu extends StatelessWidget {
  const AjandaRaporu({super.key, required this.api});

  final ApiIstemci api;

  @override
  Widget build(BuildContext context) {
    return RaporPaneli(
      api: api,
      tur: 'ajanda',
      secimler: (f) => const [],
      icerik: (c, veri, f, uygula) => [
        _AjandaGovde(veri: veri, f: f, uygula: uygula),
      ],
    );
  }
}

class _AjandaGovde extends StatefulWidget {
  const _AjandaGovde({
    required this.veri,
    required this.f,
    required this.uygula,
  });

  final Map<String, dynamic> veri;
  final RaporFiltre f;
  final void Function(RaporFiltre) uygula;

  @override
  State<_AjandaGovde> createState() => _AjandaGovdeState();
}

class _AjandaGovdeState extends State<_AjandaGovde> {
  int _trend = 0;

  Map<String, dynamic> get v => widget.veri;

  Widget _kutu(String baslik, IconData ikon, Widget cocuk, {Widget? sag}) =>
      ProgramKutu(baslik: baslik, ikon: ikon, cocuk: cocuk, sag: sag);

  static String sure(Object? dk) {
    if (dk == null) return '—';
    final d = sayiDeger(dk).toInt();
    return d >= 60
        ? '${d ~/ 60} sa${d % 60 > 0 ? ' ${d % 60} dk' : ''}'
        : '$d dk';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final k = Map<String, dynamic>.from(v['kpi'] as Map);
    final karsi =
        widget.f.karsilastir && (v['aralik'] as Map)['onceki'] != null;
    final toplam = sayiDeger(k['toplam']);
    final seri = Map<String, dynamic>.from(v['seri'] as Map);
    final seriVeri = [for (final e in (seri['veri'] as List)) sayiDeger(e)];
    final hafta = [for (final e in (v['hafta'] as List)) sayiDeger(e)];
    final saat = [for (final e in (v['saat'] as List)) sayiDeger(e)];
    final yer = liste(v['yer']);
    final yaklasan = liste(v['yaklasan']);
    final randevuDurum = liste(v['randevu_durum']);
    final yogun = k['yogun'] as Map?;
    final gun = sayiDeger((v['aralik'] as Map)['gun']);

    final icgoru = <Icgoru>[];
    if (karsi && sayiDeger(k['onceki']) > 0) {
      final y =
          (toplam - sayiDeger(k['onceki'])) * 100 / sayiDeger(k['onceki']);
      icgoru.add(
        Icgoru(
          y >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          y >= 0 ? const Color(0xFF1F8A5B) : const Color(0xFFB3202F),
          'Program sayısı önceki döneme göre **%${sayi(y.abs(), 1)}${y >= 0 ? ' arttı' : ' azaldı'}** (${sayi(k['onceki'])} → ${sayi(toplam)}).',
        ),
      );
    }
    final hm = hafta.isEmpty ? 0 : hafta.reduce((a, b) => a > b ? a : b);
    if (hm > 0 && toplam > 0) {
      icgoru.add(
        Icgoru(
          Icons.calendar_view_week_rounded,
          const Color(0xFF1D6FB8),
          'En yoğun gün **${raporGunlerUzun[hafta.indexOf(hm)]}** (%${sayi(hm * 100 / toplam, 1)}).',
        ),
      );
    }
    final sm = saat.isEmpty ? 0 : saat.reduce((a, b) => a > b ? a : b);
    if (sm > 0) {
      icgoru.add(
        Icgoru(
          Icons.schedule_rounded,
          const Color(0xFF7B4FB3),
          'En yoğun saat dilimi **${saat.indexOf(sm).toString().padLeft(2, '0')}:00** (${sayi(sm)} program).',
        ),
      );
    }
    if (yer.isNotEmpty) {
      icgoru.add(
        Icgoru(
          Icons.place_outlined,
          const Color(0xFF0F8B9C),
          'En sık mekân **${yer.first['ad']}**: ${sayi(yer.first['c'])} kez.',
        ),
      );
    }
    if (yogun != null) {
      icgoru.add(
        Icgoru(
          Icons.bolt_rounded,
          const Color(0xFFC77D0A),
          'En yoğun gün **${tarihTr(yogun['gun'])}**: ${sayi(yogun['c'])} program.',
        ),
      );
    }
    if (k['sure'] != null && sayiDeger(k['sure']) > 0) {
      icgoru.add(
        Icgoru(
          Icons.hourglass_bottom_rounded,
          const Color(0xFFB71C2B),
          'Programlar ortalama **${sure(k['sure'])}** sürüyor.',
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
              ad: 'Toplam program',
              ikon: Icons.event_available_outlined,
              renk: const Color(0xFFB71C2B),
              deger: sayi(toplam),
              delta: karsi
                  ? DeltaRozet(simdi: toplam, once: sayiDeger(k['onceki']))
                  : null,
              alt: karsi ? 'Önceki: ${sayi(k['onceki'])}' : '',
              spark: seriVeri,
            ),
            KpiVeri(
              ad: 'Haftalık ortalama',
              ikon: Icons.speed_rounded,
              renk: const Color(0xFF1D6FB8),
              deger: sayi(k['haftalik'], 1),
              alt: yogun != null
                  ? 'En yoğun: ${tarihTr(yogun['gun'], kisa: true)} (${yogun['c']})'
                  : '',
            ),
            KpiVeri(
              ad: 'Ortalama süre',
              ikon: Icons.hourglass_bottom_rounded,
              renk: const Color(0xFF7B4FB3),
              deger: sure(k['sure']),
              alt: 'Bitiş saati girilenlerde',
            ),
            KpiVeri(
              ad: 'Hatırlatıcılı',
              ikon: Icons.notifications_none_rounded,
              renk: const Color(0xFFC77D0A),
              deger: toplam > 0
                  ? '%${sayi(sayiDeger(k['hatirlatici']) * 100 / toplam)}'
                  : '—',
              alt: '${sayi(k['hatirlatici'])} programda',
            ),
            KpiVeri(
              ad: 'Farklı mekân',
              ikon: Icons.place_outlined,
              renk: const Color(0xFF0F8B9C),
              deger: sayi(k['yer_sayi']),
              alt: 'Seçili dönemde',
            ),
            KpiVeri(
              ad: 'Randevu',
              ikon: Icons.handshake_outlined,
              renk: const Color(0xFF1F8A5B),
              deger: sayi(k['randevu']),
              alt: 'Seçili dönemde',
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
          'Bugün · bu hafta',
          Icons.wb_sunny_outlined,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    sayi(k['bugun']),
                    style: tema.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'program bugün\n${sayi(k['bu_hafta'])} program bu hafta',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                sayiDeger(k['bugun']) > 0
                    ? 'Bugünkü programlarınızı Programlar sayfasından görebilirsiniz.'
                    : 'Bugün için planlanmış program görünmüyor.',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _kutu(
          'Yaklaşan programlar (14 gün)',
          Icons.notifications_active_outlined,
          yaklasan.isEmpty
              ? const BosVeri('Önümüzdeki 14 günde program yok')
              : Column(
                  children: [
                    for (final m in yaklasan)
                      TarihSatiri(
                        tarih: '${m['tarih']}',
                        baslik: '${m['ad']}',
                        alt: [
                          if ('${m['tarih']}'.length >= 16)
                            '${m['tarih']}'.substring(11, 16),
                          if (('${m['yer'] ?? ''}').isNotEmpty) '${m['yer']}',
                        ].join(' · '),
                      ),
                  ],
                ),
        ),
        _kutu(
          'Randevu durumları',
          Icons.handshake_outlined,
          randevuDurum.isEmpty
              ? const BosVeri('Randevu yok')
              : HalkaGrafik(
                  ogeler: [
                    for (var i = 0; i < randevuDurum.length; i++)
                      BarOge(
                        '${randevuDurum[i]['ad']}',
                        sayiDeger(randevuDurum[i]['c']),
                        renk: raporRenkleri[(i + 2) % raporRenkleri.length],
                      ),
                  ],
                  birim: 'randevu',
                ),
        ),
        _kutu(
          'Program trendi',
          Icons.show_chart_rounded,
          TrendGrafik(
            seri: seri,
            cubuk: _trend == 1,
            karsilastir: karsi,
            ad: 'Program',
          ),
          sag: MiniSecici(
            secenekler: const ['Çizgi', 'Çubuk'],
            secili: _trend,
            degisti: (i) => setState(() => _trend = i),
          ),
        ),
        _kutu(
          'Haftanın günlerine göre',
          Icons.calendar_view_week_rounded,
          SutunGrafik(etiketler: raporGunler, degerler: hafta),
        ),
        _kutu(
          'Harita · programların yer dağılımı',
          Icons.public_rounded,
          RaporHaritasi(
            veri: nesne(v['harita']),
            birim: 'program',
            ilSec: (id) => widget.uygula(widget.f.kopya(il: id)),
            ilTemizle: () => widget.uygula(widget.f.kopya(il: 0)),
          ),
        ),
        _kutu(
          'Saat dağılımı',
          Icons.schedule_rounded,
          SutunGrafik(
            etiketler: [
              for (var i = 0; i < 24; i++)
                i % 3 == 0 ? i.toString().padLeft(2, '0') : '',
            ],
            degerler: saat,
          ),
        ),
        _kutu(
          'En sık mekânlar',
          Icons.place_outlined,
          BarListe(
            ogeler: [
              for (final x in yer) BarOge('${x['ad']}', sayiDeger(x['c'])),
            ],
            toplam: toplam,
            renk: const Color(0xFF0F8B9C),
          ),
        ),
        _kutu(
          'Ünvan / kurum dağılımı',
          Icons.badge_outlined,
          BarListe(
            ogeler: [
              for (final x in liste(v['unvan']))
                BarOge('${x['ad']}', sayiDeger(x['c'])),
            ],
            toplam: toplam,
            renk: const Color(0xFF7B4FB3),
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
          'Randevu kategorileri',
          Icons.layers_outlined,
          BarListe(
            ogeler: [
              for (final x in liste(v['randevu_kat']))
                BarOge('${x['ad']}', sayiDeger(x['c'])),
            ],
          ),
        ),
        _kutu(
          'Programı giren yönetici',
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
          'Tekrarlayan programlar',
          Icons.repeat_rounded,
          liste(v['konu']).isEmpty
              ? const BosVeri('Tekrarlayan program yok')
              : Column(
                  children: [
                    for (final x in liste(v['konu']).indexed)
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
                                '${x.$1 + 1}',
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
                                '${x.$2['ad']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              sayi(x.$2['c']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
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
                'Program olan gün/hafta/ay',
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
