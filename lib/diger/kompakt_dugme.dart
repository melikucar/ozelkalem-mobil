import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'premium_gezinti.dart';

/// Modüllerdeki "Yeni …" / "Düzenle" eylemi için küçük, premium hap düğme (FloatingActionButton.extended yerine).
/// Parmakla sürüklenerek ekranda istenen yere taşınabilir (arkadaki içeriği ya da formu kapatıyorsa); başka bir sayfaya ya da
/// sekmeye geçince (üstüne başka sayfa açılınca ya da sekme gizlenince) konumu sıfırlanır, düğme eski yerine döner.
class KompaktDugme extends StatefulWidget {
  const KompaktDugme({
    super.key,
    required this.etiket,
    required this.onPressed,
    this.ikon = Icons.add_rounded,
    this.tasinabilir = true,
  });

  final String etiket;
  final IconData ikon;
  final VoidCallback? onPressed;

  /// false: sürüklenemez (varsayılan: sürüklenebilir).
  final bool tasinabilir;

  @override
  State<KompaktDugme> createState() => _KompaktDugmeState();
}

class _KompaktDugmeState extends State<KompaktDugme> {
  /// Varsayılan yerden sapma; yalnız bu sayfa görünürken geçerlidir.
  Offset _kayma = Offset.zero;
  Animation<double>? _ikincil;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // sekme gizlendi (başka sekmeye geçildi): konumu sıfırla
    if (!TickerMode.valuesOf(context).enabled && _kayma != Offset.zero) {
      _kayma = Offset.zero;
    }
    // üstüne başka bir sayfa açıldı (ayrıntı, form…): konumu sıfırla
    final yeni = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(yeni, _ikincil)) {
      _ikincil?.removeStatusListener(_rotaDurumu);
      _ikincil = yeni;
      _ikincil?.addStatusListener(_rotaDurumu);
    }
  }

  void _rotaDurumu(AnimationStatus d) {
    if (d != AnimationStatus.dismissed && _kayma != Offset.zero && mounted) {
      setState(() => _kayma = Offset.zero);
    }
  }

  @override
  void dispose() {
    _ikincil?.removeStatusListener(_rotaDurumu);
    super.dispose();
  }

  void _surukle(BuildContext c, DragUpdateDetails d) {
    // c: taşınan düğmenin kendi bağlamı; localToGlobal kaymış (gerçek) konumu verir
    final kutu = c.findRenderObject() as RenderBox;
    final ekran = MediaQuery.sizeOf(context);
    final ust = MediaQuery.paddingOf(context).top + 8;
    final p = kutu.localToGlobal(Offset.zero);
    final yeni = Offset(
      (p.dx + d.delta.dx).clamp(8.0, ekran.width - kutu.size.width - 8),
      (p.dy + d.delta.dy).clamp(ust, ekran.height - kutu.size.height - 8),
    );
    final k = _kayma + (yeni - p);
    // varsayılan konumun sağına/altına taşınamaz (yuva o yönde genişlemez)
    setState(() => _kayma = Offset(k.dx > 0 ? 0 : k.dx, k.dy > 0 ? 0 : k.dy));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = cs.primary;
    final b = Color.lerp(a, Colors.black, 0.28)!;
    final govde = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
        boxShadow: [
          BoxShadow(
            color: a.withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 0, 15, 0),
            child: SizedBox(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.ikon, size: 18, color: cs.onPrimary),
                  const SizedBox(width: 6),
                  Text(
                    widget.etiket,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.tasinabilir) return govde;
    return _Tasinan(
      kayma: _kayma,
      child: Builder(
        builder: (c) =>
            GestureDetector(onPanUpdate: (d) => _surukle(c, d), child: govde),
      ),
    );
  }
}

/// Alt gezinti çubuğunun (profil düğmesinin) hemen üstünde, onunla aynı sağ kenara hizalı konum. Gövde çubuğun arkasına
/// uzandığı için (extendBody) varsayılan konum çubuğun altında kalır.
class BarUstuKonum extends FloatingActionButtonLocation {
  const BarUstuKonum();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) {
    final alt = g.minViewPadding.bottom;
    final bar = PremiumGezinti.yukseklik + (alt > 0 ? alt : 6);
    return Offset(
      g.scaffoldSize.width - g.floatingActionButtonSize.width - 16,
      g.scaffoldSize.height - g.floatingActionButtonSize.height - bar - 24,
    );
  }
}

/// Taşınabilir düğmenin yerleşimi. Scaffold, FAB yuvasının dışındaki dokunuşları düğmeye iletmez; bu yüzden düğme bir kez taşınınca
/// bir daha tutulamazdı. Çözüm: düğme taşınmışken yuva, varsayılan konumla taşınmış konumu kapsayacak kadar genişler (sağ-alt köşe
/// varsayılan konumla aynı kaldığından düğme yerinden oynamaz); taşınmamışken yuva düğmenin kendi boyutundadır.
/// Düğme yalnız varsayılan konumunun yukarısına/soluna taşınabilir (kayma hiçbir zaman pozitif olmaz).
class _Tasinan extends SingleChildRenderObjectWidget {
  const _Tasinan({required this.kayma, super.child});

  final Offset kayma;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTasinan(kayma);

  @override
  void updateRenderObject(BuildContext context, _RenderTasinan renderObject) {
    renderObject.kayma = kayma;
  }
}

class _RenderTasinan extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderTasinan(this._kayma);

  Offset _kayma;
  Offset _cocukKonumu = Offset.zero;

  set kayma(Offset v) {
    if (_kayma == v) return;
    _kayma = v;
    markNeedsLayout();
  }

  bool get _genis => _kayma != Offset.zero;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.loosen(), parentUsesSize: true);
    if (_genis) {
      // yuva, varsayılan konum (sağ-alt) ile taşınmış konumu kapsayan en küçük dikdörtgen olur (kayma yalnız yukarı/sola)
      size = constraints.constrain(
        Size(c.size.width - _kayma.dx, c.size.height - _kayma.dy),
      );
      _cocukKonumu =
          Offset(size.width - c.size.width, size.height - c.size.height) +
          _kayma;
    } else {
      size = c.size;
      _cocukKonumu = Offset.zero;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + _cocukKonumu);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_cocukKonumu.dx, _cocukKonumu.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: _cocukKonumu,
      position: position,
      hitTest: (BoxHitTestResult r, Offset p) => c.hitTest(r, position: p),
    );
  }
}
