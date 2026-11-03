import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Makamın görseli (ayarlar.logo): altın halkalı yuvarlak. Yüz üstte kalacak şekilde kırpılır.
/// Görsel yoksa ya da henüz inmediyse makam adının baş harfleri gösterilir.
class MakamAvatari extends StatelessWidget {
  const MakamAvatari({super.key, this.resim, this.ad = '', this.boyut = 72});

  final Uint8List? resim;
  final String ad;
  final double boyut;

  String get _basHarfler {
    final p = ad
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (p.isEmpty) return '';
    final ilk = p.first.substring(0, 1);
    final son = p.length > 1 ? p.last.substring(0, 1) : '';
    return (ilk + son).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final yedek = Container(
      color: Marka.lacivert2,
      alignment: Alignment.center,
      child: _basHarfler.isEmpty
          ? Icon(Icons.person_outline, color: Marka.altin, size: boyut * 0.5)
          : Text(
              _basHarfler,
              style: TextStyle(
                color: Marka.altin,
                fontWeight: FontWeight.w600,
                fontSize: boyut * 0.34,
                letterSpacing: 0.7,
              ),
            ),
    );
    return Container(
      width: boyut,
      height: boyut,
      padding: EdgeInsets.all(boyut * 0.045),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0.9),
            Colors.white.withValues(alpha: 0.35),
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.22),
            blurRadius: 14,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: resim != null
            ? Image.memory(
                resim!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => yedek,
              )
            : yedek,
      ),
    );
  }
}

/// Marka işareti (elmas halka) ve yükleme göstergesi: açılış / bekleme ekranları için.
class MarkaYukleniyor extends StatelessWidget {
  const MarkaYukleniyor({super.key, this.mesaj});

  final String? mesaj;

  @override
  Widget build(BuildContext context) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/marka/isaret.png', width: 88, height: 88),
          const SizedBox(height: 24),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              borderRadius: BorderRadius.circular(4),
              color: koyu ? Marka.camgobegi : Marka.mavi,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
          if (mesaj != null) ...[
            const SizedBox(height: 16),
            Text(mesaj!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
