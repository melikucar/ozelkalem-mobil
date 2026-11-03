import 'dart:async';

import 'package:flutter/material.dart';

import 'bildirim_servisi.dart';

/// Uygulama açıkken gelen bildirimi ekranın üstünde kayarak gösterir; 5 sn sonra, dokununca ya da yukarı kaydırınca kapanır.
class BildirimToast extends StatefulWidget {
  const BildirimToast({super.key, required this.child});

  final Widget child;

  @override
  State<BildirimToast> createState() => _BildirimToastState();
}

class _BildirimToastState extends State<BildirimToast> {
  final _servis = BildirimServisi.ornek;
  BildirimIcerigi? _gorunen;
  bool _acik = false;
  Timer? _zaman;

  @override
  void initState() {
    super.initState();
    _servis.toast.addListener(_geldi);
  }

  @override
  void dispose() {
    _servis.toast.removeListener(_geldi);
    _zaman?.cancel();
    super.dispose();
  }

  void _geldi() {
    final b = _servis.toast.value;
    if (b == null) return;
    _zaman?.cancel();
    setState(() {
      _gorunen = b;
      _acik = true;
    });
    _zaman = Timer(const Duration(seconds: 5), _kapat);
  }

  void _kapat() {
    if (!mounted) return;
    setState(() => _acik = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ust = MediaQuery.paddingOf(context).top;
    final b = _gorunen;
    return Stack(
      children: [
        widget.child,
        if (b != null)
          Positioned(
            top: ust + 8,
            left: 12,
            right: 12,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 380),
              curve: _acik ? Curves.easeOutBack : Curves.easeInCubic,
              offset: _acik ? Offset.zero : const Offset(0, -1.6),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _acik ? 1 : 0,
                child: Material(
                  type: MaterialType.transparency,
                  child: GestureDetector(
                    onTap: _kapat,
                    onVerticalDragUpdate: (d) {
                      if (d.delta.dy < -4) _kapat();
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xF2101C2E),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primary,
                            ),
                            child: Icon(
                              Icons.notifications_active_rounded,
                              size: 20,
                              color: cs.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.baslik,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (b.govde.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      b.govde,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFC3CFDE),
                                        fontSize: 12.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
