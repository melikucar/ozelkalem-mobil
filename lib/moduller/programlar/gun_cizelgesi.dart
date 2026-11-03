import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/program.dart';
import '../../veri/program_deposu.dart';
import 'program_ortak.dart';

/// Gün görünümü: saat çizgili zaman çizelgesi. Programlar zamanına göre konumlanır, çakışanlar yan yana dizilir.
/// - Programa uzun basıp sürükleyerek zamanını değiştirirsiniz (15 dk adımlarla); alt kenardaki tutamaçla süreyi uzatır/kısaltırsınız.
/// - Boş bir alana uzun basmak o saatte yeni program açar.
/// - Bugünse kırmızı "şimdi" çizgisi görünür. "Gün boyu" programlar üstteki şeritte durur.
class GunCizelgesi extends StatefulWidget {
  const GunCizelgesi({
    super.key,
    required this.gun,
    required this.programlar,
    required this.depo,
    required this.ac,
    required this.yeni,
    required this.sorunlu,
  });

  final DateTime gun;
  final List<Program> programlar;
  final ProgramDeposu depo;
  final void Function(Program) ac;
  final void Function(DateTime) yeni;
  final Set<int> sorunlu;

  @override
  State<GunCizelgesi> createState() => _GunCizelgesiState();
}

class _Yerlesim {
  _Yerlesim(this.p, this.bas, this.bit);

  final Program p;
  final DateTime bas;
  final DateTime bit;
  int sutun = 0;
  int sutunSayisi = 1;
}

class _GunCizelgesiState extends State<GunCizelgesi> {
  static const _saatYuk = 64.0;
  static const _sol = 50.0;
  static const _adim = 15; // dakika

  late final ScrollController _kaydirma = ScrollController(
    initialScrollOffset: _baslangicKaydirmasi(),
  );

  int? _suruklenen; // yerel id
  int _tasiDk = 0;
  int _boyutDk = 0;
  bool _surukleniyor = false;

  double _baslangicKaydirmasi() {
    final g = gunBasi(widget.gun);
    final simdi = DateTime.now();
    double saatOf(DateTime t) => t.isBefore(g) ? 0.0 : t.hour + t.minute / 60;
    final zamanli = widget.programlar.where((p) => !p.tumGun);
    double saat;
    if (ayniGun(simdi, g)) {
      // Bugün: bitmemiş ilk programa (yoksa şimdiye) odaklan
      final kalan = zamanli.where((p) => p.bit.isAfter(simdi)).toList()
        ..sort((a, b) => a.bas.compareTo(b.bas));
      saat = kalan.isNotEmpty
          ? math.min(
                  saatOf(kalan.first.bas),
                  math.max(saatOf(simdi), saatOf(kalan.first.bas)),
                ) -
                1
          : saatOf(simdi) - 1.5;
    } else {
      final ilk = zamanli
          .map((p) => saatOf(p.bas))
          .fold<double?>(null, (a, b) => a == null ? b : math.min(a, b));
      saat = (ilk ?? 8) - 1;
    }
    return (saat.clamp(0, 24 - 8)) * _saatYuk;
  }

  @override
  void didUpdateWidget(GunCizelgesi eski) {
    super.didUpdateWidget(eski);
    if (!ayniGun(eski.gun, widget.gun) && _kaydirma.hasClients) {
      _kaydirma.jumpTo(
        _baslangicKaydirmasi().clamp(0, _kaydirma.position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    _kaydirma.dispose();
    super.dispose();
  }

  /// Günün içine kırpılmış, zamanlı programlar ve çakışma sütunları.
  List<_Yerlesim> _yerlestir() {
    final g = gunBasi(widget.gun);
    final son = g.add(const Duration(days: 1));
    final liste = <_Yerlesim>[];
    for (final p in widget.programlar) {
      if (p.tumGun) continue;
      final b = p.bas.isBefore(g) ? g : p.bas;
      var e = p.bit.isAfter(son) ? son : p.bit;
      if (e.difference(b).inMinutes < 20) {
        e = b.add(
          const Duration(minutes: 20),
        ); // çok kısa programlar da dokunulabilir olsun
      }
      liste.add(_Yerlesim(p, b, e));
    }
    liste.sort((a, b) => a.bas.compareTo(b.bas));
    // Çakışan gruplar: aynı grupta sütun ataması
    var grup = <_Yerlesim>[];
    DateTime? grupSonu;
    void kapat() {
      final n = grup.fold<int>(0, (a, y) => math.max(a, y.sutun + 1));
      for (final y in grup) {
        y.sutunSayisi = n;
      }
      grup = [];
      grupSonu = null;
    }

    for (final y in liste) {
      if (grupSonu != null && !y.bas.isBefore(grupSonu!)) kapat();
      final kullanilan = {
        for (final o in grup)
          if (o.bit.isAfter(y.bas)) o.sutun,
      };
      var s = 0;
      while (kullanilan.contains(s)) {
        s++;
      }
      y.sutun = s;
      grup.add(y);
      grupSonu = grupSonu == null || y.bit.isAfter(grupSonu!)
          ? y.bit
          : grupSonu;
    }
    kapat();
    return liste;
  }

  double _y(DateTime t) {
    final g = gunBasi(widget.gun);
    return t.difference(g).inMinutes / 60 * _saatYuk;
  }

  int _dakika(double dy) => (dy / _saatYuk * 60 / _adim).round() * _adim;

  Future<void> _tasiBitir(_Yerlesim y) async {
    final dk = _tasiDk;
    final bd = _boyutDk;
    setState(() {
      _suruklenen = null;
      _surukleniyor = false;
      _tasiDk = 0;
      _boyutDk = 0;
    });
    if (dk == 0 && bd == 0) return;
    final yeniBas = y.p.bas.add(Duration(minutes: dk));
    var yeniBit = y.p.bit.add(Duration(minutes: dk + bd));
    if (yeniBit.difference(yeniBas).inMinutes < _adim) {
      yeniBit = yeniBas.add(const Duration(minutes: _adim));
    }
    await widget.depo.tasi(y.p.yerelId!, yeniBas, yeniBit);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final yerlesimler = _yerlestir();
    final gunBoyu = widget.programlar.where((p) => p.tumGun).toList();
    final bugunMu = ayniGun(DateTime.now(), widget.gun);
    final simdi = DateTime.now();

    return Column(
      children: [
        if (gunBoyu.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in gunBoyu)
                  ActionChip(
                    avatar: Icon(
                      Icons.wb_sunny_outlined,
                      size: 16,
                      color: p.renk,
                    ),
                    label: Text(
                      p.adi,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: p.renk.withValues(alpha: 0.6)),
                    backgroundColor: p.renk.withValues(alpha: 0.10),
                    onPressed: () => widget.ac(p),
                  ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, k) {
              final alan = k.maxWidth - _sol - 14;
              return SingleChildScrollView(
                controller: _kaydirma,
                physics: _surukleniyor
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 110),
                child: SizedBox(
                  height: 24 * _saatYuk + 8,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // saat çizgileri ve etiketleri
                      for (var h = 0; h <= 24; h++)
                        Positioned(
                          top: h * _saatYuk,
                          left: 0,
                          right: 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: _sol,
                                child: Transform.translate(
                                  offset: const Offset(0, -7),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      h == 24
                                          ? ''
                                          : '${h.toString().padLeft(2, '0')}:00',
                                      textAlign: TextAlign.right,
                                      style: tema.textTheme.labelSmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 10.5,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  height: 1,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                            ],
                          ),
                        ),
                      // boş alana uzun basma: yeni program
                      Positioned(
                        left: _sol,
                        right: 0,
                        top: 0,
                        height: 24 * _saatYuk,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onLongPressStart: (d) {
                            HapticFeedback.mediumImpact();
                            final dk =
                                (d.localPosition.dy / _saatYuk * 60 / 30)
                                    .floor() *
                                30;
                            widget.yeni(
                              gunBasi(widget.gun).add(Duration(minutes: dk)),
                            );
                          },
                        ),
                      ),
                      for (final y in yerlesimler)
                        _blok(context, y, alan, tema),
                      if (bugunMu)
                        Positioned(
                          top: _y(simdi) - 5,
                          left: _sol - 6,
                          right: 6,
                          child: IgnorePointer(
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE5362B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const Expanded(
                                  child: Divider(
                                    height: 2,
                                    thickness: 2,
                                    color: Color(0xFFE5362B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _blok(BuildContext context, _Yerlesim y, double alan, ThemeData tema) {
    final p = y.p;
    final surukleniyor = _suruklenen == p.yerelId;
    final tasinabilir =
        ayniGun(p.bas, widget.gun) &&
        !p.bit.isAfter(gunBasi(widget.gun).add(const Duration(days: 1)));
    final genislik = alan / y.sutunSayisi;
    final left = _sol + y.sutun * genislik;
    final top = _y(y.bas) + (surukleniyor ? _tasiDk / 60 * _saatYuk : 0);
    var yuk =
        math.max(_y(y.bit) - _y(y.bas), 22.0) +
        (surukleniyor ? _boyutDk / 60 * _saatYuk : 0);
    yuk = math.max(yuk, 22.0);
    final renk = p.renk;
    final acik = tema.brightness == Brightness.light;
    final durum = programZamaniDurumu(p);
    final gecmis = durum == ProgramZamani.gecmis;
    final bas = surukleniyor ? p.bas.add(Duration(minutes: _tasiDk)) : y.bas;
    var bit = surukleniyor
        ? p.bit.add(Duration(minutes: _tasiDk + _boyutDk))
        : y.bit;
    if (surukleniyor && bit.difference(bas).inMinutes < _adim) {
      bit = bas.add(const Duration(minutes: _adim));
    }
    final sorun = widget.sorunlu.contains(p.yerelId);

    return AnimatedPositioned(
      duration: surukleniyor
          ? Duration.zero
          : const Duration(milliseconds: 160),
      top: top,
      left: left + 2,
      width: genislik - 4,
      height: yuk - 2,
      child: GestureDetector(
        onTap: () => widget.ac(p),
        onLongPressStart: tasinabilir
            ? (_) {
                HapticFeedback.mediumImpact();
                setState(() {
                  _suruklenen = p.yerelId;
                  _surukleniyor = true;
                  _tasiDk = 0;
                  _boyutDk = 0;
                });
              }
            : null,
        onLongPressMoveUpdate: tasinabilir
            ? (d) {
                final dk = _dakika(d.offsetFromOrigin.dy);
                if (dk != _tasiDk) {
                  HapticFeedback.selectionClick();
                  setState(() => _tasiDk = dk);
                }
              }
            : null,
        onLongPressEnd: tasinabilir ? (_) => _tasiBitir(y) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Color.alphaBlend(
              renk.withValues(alpha: acik ? 0.16 : 0.30),
              tema.colorScheme.surface,
            ),
            border: Border(left: BorderSide(color: renk, width: 4)),
            boxShadow: surukleniyor
                ? [
                    BoxShadow(
                      color: renk.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Opacity(
                opacity: gecmis && !surukleniyor ? 0.6 : 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
                  child: ClipRect(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.adi,
                          maxLines: yuk > 52 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: tema.colorScheme.onSurface,
                          ),
                        ),
                        if (yuk > 38)
                          Text(
                            '${saatYaz(bas)} – ${saatYaz(bit)}'
                            '${p.yer.isNotEmpty && yuk > 60 ? ' · ${p.yer}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: tema.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (sorun || p.bekleyen)
                Positioned(
                  top: 3,
                  right: 4,
                  child: Icon(
                    sorun
                        ? Icons.warning_amber_rounded
                        : Icons.cloud_upload_outlined,
                    size: 14,
                    color: sorun
                        ? Colors.amber.shade800
                        : tema.colorScheme.outline,
                  ),
                ),
              if (tasinabilir)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 18,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      setState(() {
                        _suruklenen = p.yerelId;
                        _surukleniyor = true;
                        _tasiDk = 0;
                        _boyutDk = 0;
                      });
                    },
                    onVerticalDragUpdate: (d) {
                      _boyutToplam += d.delta.dy;
                      final dk = _dakika(_boyutToplam);
                      if (dk != _boyutDk) {
                        HapticFeedback.selectionClick();
                        setState(() => _boyutDk = dk);
                      }
                    },
                    onVerticalDragEnd: (_) {
                      _boyutToplam = 0;
                      _tasiBitir(y);
                    },
                    onVerticalDragCancel: () {
                      _boyutToplam = 0;
                      setState(() {
                        _suruklenen = null;
                        _surukleniyor = false;
                        _boyutDk = 0;
                      });
                    },
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        width: 22,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: renk.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _boyutToplam = 0;
}
