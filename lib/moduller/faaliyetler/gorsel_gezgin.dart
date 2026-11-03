import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import 'faaliyet_ortak.dart';

/// Faaliyet fotoğraflarını tam ekranda gösterir: yana kaydırarak diğer resimlere geçilir, iki parmakla yakınlaştırılır.
/// [resimler]: `{ad, goruntu}` içeren ek dosya kayıtları.
Future<void> gorselGezginiAc(
  BuildContext context, {
  required ApiIstemci api,
  required int no,
  required List<Map<String, dynamic>> resimler,
  int ilk = 0,
}) => showDialog<void>(
  context: context,
  useSafeArea: false,
  builder: (_) => _GorselGezgin(api: api, no: no, resimler: resimler, ilk: ilk),
);

class _GorselGezgin extends StatefulWidget {
  const _GorselGezgin({
    required this.api,
    required this.no,
    required this.resimler,
    required this.ilk,
  });

  final ApiIstemci api;
  final int no;
  final List<Map<String, dynamic>> resimler;
  final int ilk;

  @override
  State<_GorselGezgin> createState() => _GorselGezginState();
}

class _GorselGezginState extends State<_GorselGezgin> {
  late final PageController _kontrol = PageController(initialPage: widget.ilk);
  late int _simdi = widget.ilk;
  final _donusumler = <int, TransformationController>{};
  bool _yakin = false; // yakınlaştırılmışken sayfa kaydırması kapanır

  @override
  void dispose() {
    _kontrol.dispose();
    for (final d in _donusumler.values) {
      d.dispose();
    }
    super.dispose();
  }

  String _yol(int i) =>
      'faaliyetler/dosya?no=${widget.no}&ad=${Uri.encodeQueryComponent('${widget.resimler[i]['ad']}')}';

  void _git(int i) => _kontrol.animateToPage(
    i,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final toplam = widget.resimler.length;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _kontrol,
              itemCount: toplam,
              physics: _yakin
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (i) => setState(() {
                _simdi = i;
                _yakin = false;
              }),
              itemBuilder: (c, i) {
                final d = _donusumler.putIfAbsent(
                  i,
                  TransformationController.new,
                );
                return InteractiveViewer(
                  transformationController: d,
                  minScale: 1,
                  maxScale: 6,
                  onInteractionEnd: (_) {
                    final yakin = d.value.getMaxScaleOnAxis() > 1.05;
                    if (yakin != _yakin) setState(() => _yakin = yakin);
                  },
                  child: Center(
                    child: FutureBuilder<Uint8List?>(
                      future: FaaliyetGorselleri.getir(widget.api, _yol(i)),
                      builder: (c, s) {
                        if (s.data != null) {
                          return Image.memory(s.data!, fit: BoxFit.contain);
                        }
                        if (s.connectionState == ConnectionState.done) {
                          return const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 48,
                          );
                        }
                        return const CircularProgressIndicator(
                          color: Colors.white70,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (toplam > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_simdi + 1} / $toplam',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (toplam > 1) ...[
            if (_simdi > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: _Ok(
                  ikon: Icons.chevron_left_rounded,
                  tikla: () => _git(_simdi - 1),
                ),
              ),
            if (_simdi < toplam - 1)
              Align(
                alignment: Alignment.centerRight,
                child: _Ok(
                  ikon: Icons.chevron_right_rounded,
                  tikla: () => _git(_simdi + 1),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < toplam; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _simdi ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _simdi ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Ok extends StatelessWidget {
  const _Ok({required this.ikon, required this.tikla});

  final IconData ikon;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: tikla,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(ikon, color: Colors.white, size: 28),
        ),
      ),
    ),
  );
}
