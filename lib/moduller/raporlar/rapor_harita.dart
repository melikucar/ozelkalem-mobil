import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

import 'rapor_ortak.dart';

class _Bolge {
  _Bolge(this.id, this.ad, this.yol, this.lx, this.ly);

  final int id;
  final String ad;
  final Path yol;
  final double lx;
  final double ly;
}

class _Harita {
  _Harita(this.genislik, this.yukseklik, this.bolgeler);

  final double genislik;
  final double yukseklik;
  final List<_Bolge> bolgeler;
}

/// Haritaların (assets/harita) yüklenmesi ve çözümlenmesi; bir kez yapılır.
class _Yukleyici {
  static final _onbellek = <String, Future<_Harita?>>{};

  static Future<_Harita?> il() =>
      _onbellek['il'] ??= _yukle('assets/harita/il.json', 'iller');

  static Future<_Harita?> ilce(int plaka) =>
      _onbellek['i$plaka'] ??= _yukle('assets/harita/ilce/$plaka.json', 'i');

  static Future<_Harita?> _yukle(String yol, String anahtar) async {
    try {
      final j = jsonDecode(await rootBundle.loadString(yol)) as Map;
      final g = (j['genislik'] ?? j['g'] as num).toDouble();
      final y = (j['yukseklik'] ?? j['y'] as num).toDouble();
      final bolgeler = <_Bolge>[];
      for (final r in (j[anahtar] as List)) {
        final l = r as List;
        final ad = l.length > 4 ? '${l[4]}' : '${l[1]}';
        // il: [plaka, ad, yol, x, y]; ilçe: [id, yol, x, y, ad]
        final ilMi = anahtar == 'iller';
        bolgeler.add(
          _Bolge(
            (l[0] as num).toInt(),
            ilMi ? '${l[1]}' : ad,
            parseSvgPathData(ilMi ? '${l[2]}' : '${l[1]}'),
            (l[ilMi ? 3 : 2] as num).toDouble(),
            (l[ilMi ? 4 : 3] as num).toDouble(),
          ),
        );
      }
      return _Harita(g, y, bolgeler);
    } catch (_) {
      return null;
    }
  }
}

/// Türkiye ısı haritası + seçili ilin ilçe haritası (web `RaporHarita` ile aynı veri).
/// Veri: iller {plaka: adet}, belirsiz, il_id {plaka: tbl_il no}, odak (plaka), odak_ad, ilceler {tbl_ilce no: adet},
/// ilce_belirsiz, ilce_adlar {tbl_ilce no: ad}. İle dokununca ayrıntısı altta çıkar; "Süzgeç yap" o ili süzgeç olarak uygular.
class RaporHaritasi extends StatefulWidget {
  const RaporHaritasi({
    super.key,
    required this.veri,
    required this.birim,
    required this.ilSec,
    required this.ilTemizle,
  });

  final Map<String, dynamic> veri;
  final String birim;
  final void Function(int ilId) ilSec;
  final VoidCallback ilTemizle;

  @override
  State<RaporHaritasi> createState() => _RaporHaritasiState();
}

class _RaporHaritasiState extends State<RaporHaritasi> {
  _Harita? _il;
  _Harita? _ilce;
  int _ilceYuklenen = 0;
  bool _yukleniyor = true;
  int? _secili;

  Map<String, dynamic> get _v => widget.veri;
  int get _odak => (_v['odak'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(RaporHaritasi eski) {
    super.didUpdateWidget(eski);
    if (eski.veri != widget.veri) {
      _secili = null;
      _yukle();
    }
  }

  Future<void> _yukle() async {
    final il = await _Yukleyici.il();
    _Harita? ilce;
    if (_odak > 0) ilce = await _Yukleyici.ilce(_odak);
    if (!mounted) return;
    setState(() {
      _il = il;
      _ilce = ilce;
      _ilceYuklenen = _odak;
      _yukleniyor = false;
    });
  }

  Map<int, int> _sayilar(Object? m) => {
    for (final e in (m is Map ? m : const {}).entries)
      int.parse('${e.key}'): sayiDeger(e.value).toInt(),
  };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    if (_yukleniyor) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final ilMod = _odak > 0 && _ilce != null && _ilceYuklenen == _odak;
    final harita = ilMod ? _ilce : _il;
    if (harita == null) return const BosVeri('Harita yüklenemedi');

    final sayilar = ilMod ? _sayilar(_v['ilceler']) : _sayilar(_v['iller']);
    final belirsiz = sayiDeger(ilMod ? _v['ilce_belirsiz'] : _v['belirsiz'])
        .toInt();
    final ilIdler = _sayilar(_v['il_id']);
    final ilceAdlar = {
      for (final e
          in (_v['ilce_adlar'] is Map ? _v['ilce_adlar'] as Map : const {})
              .entries)
        int.parse('${e.key}'): '${e.value}',
    };
    String ad(_Bolge b) => ilMod ? (ilceAdlar[b.id] ?? b.ad) : b.ad;
    final toplam = sayilar.values.fold<int>(0, (a, b) => a + b);
    final mx = sayilar.values.isEmpty ? 0 : sayilar.values.reduce(math.max);
    final dolu = sayilar.values.where((c) => c > 0).length;
    final sirali = sayilar.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final secili = _secili;
    final seciliBolge = secili == null
        ? null
        : harita.bolgeler.where((b) => b.id == secili).firstOrNull;

    Color renk(int id) {
      final c = sayilar[id] ?? 0;
      if (c == 0) return cs.onSurface.withValues(alpha: 0.07);
      final t = mx <= 1 ? 0.6 : (c - 1) / (mx - 1);
      return Color.lerp(cs.primary.withValues(alpha: 0.22), cs.primary, t)!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (ilMod)
              TextButton.icon(
                onPressed: widget.ilTemizle,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Türkiye'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            Expanded(
              child: Text(
                ilMod
                    ? '${_v['odak_ad']} · ilçe dağılımı'
                    : 'İllere göre ${widget.birim} dağılımı',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: harita.genislik / harita.yukseklik,
          child: LayoutBuilder(
            builder: (context, c) {
              final olcek = c.maxWidth / harita.genislik;
              return InteractiveViewer(
                maxScale: 6,
                minScale: 1,
                child: GestureDetector(
                  onTapUp: (d) {
                    final p = d.localPosition / olcek;
                    for (final b in harita.bolgeler.reversed) {
                      if (b.yol.contains(p)) {
                        setState(() => _secili = _secili == b.id ? null : b.id);
                        return;
                      }
                    }
                    setState(() => _secili = null);
                  },
                  child: CustomPaint(
                    size: Size(c.maxWidth, c.maxHeight),
                    painter: _HaritaCizici(
                      harita: harita,
                      olcek: olcek,
                      renk: renk,
                      secili: secili,
                      cizgi: cs.surface,
                      vurgu: cs.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('0', style: tema.textTheme.bodySmall),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [cs.primary.withValues(alpha: 0.22), cs.primary],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(sayi(mx), style: tema.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 10),
        if (seciliBolge != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad(seciliBolge),
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${sayi(sayilar[seciliBolge.id] ?? 0)} ${widget.birim}',
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!ilMod && (sayilar[seciliBolge.id] ?? 0) > 0)
                  FilledButton.tonal(
                    onPressed: () {
                      final id = ilIdler[seciliBolge.id];
                      if (id != null) widget.ilSec(id);
                    },
                    child: const Text('Süzgeç yap'),
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Ozet(sayi(toplam), 'Toplam'),
            _Ozet('$dolu', ilMod ? 'İlçe' : 'İl'),
            if (belirsiz > 0) _Ozet(sayi(belirsiz), 'Çözümlenemeyen'),
            if (sirali.isNotEmpty)
              _Ozet(
                (() {
                  final b = harita.bolgeler
                      .where((x) => x.id == sirali.first.key)
                      .firstOrNull;
                  return b == null ? '—' : ad(b);
                })(),
                'En yoğun',
              ),
          ],
        ),
        const SizedBox(height: 10),
        BarListe(
          ogeler: [
            for (final e in sirali.take(8))
              BarOge(
                (() {
                  final b = harita.bolgeler
                      .where((x) => x.id == e.key)
                      .firstOrNull;
                  return b == null ? '${e.key}' : ad(b);
                })(),
                e.value,
                no: e.key,
              ),
          ],
          toplam: toplam,
          tikla: (o) => setState(() => _secili = o.no),
        ),
      ],
    );
  }
}

class _Ozet extends StatelessWidget {
  const _Ozet(this.deger, this.etiket);

  final String deger;
  final String etiket;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            deger,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            etiket,
            style: tema.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _HaritaCizici extends CustomPainter {
  _HaritaCizici({
    required this.harita,
    required this.olcek,
    required this.renk,
    required this.secili,
    required this.cizgi,
    required this.vurgu,
  });

  final _Harita harita;
  final double olcek;
  final Color Function(int) renk;
  final int? secili;
  final Color cizgi;
  final Color vurgu;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(olcek);
    final dolgu = Paint()..style = PaintingStyle.fill;
    final kenar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = cizgi
      ..strokeJoin = StrokeJoin.round;
    for (final b in harita.bolgeler) {
      dolgu.color = renk(b.id);
      canvas.drawPath(b.yol, dolgu);
      canvas.drawPath(b.yol, kenar);
    }
    final s = harita.bolgeler.where((b) => b.id == secili).firstOrNull;
    if (s != null) {
      canvas.drawPath(
        s.yol,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = vurgu,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HaritaCizici o) =>
      o.harita != harita ||
      o.secili != secili ||
      o.olcek != olcek ||
      o.renk != renk;
}
