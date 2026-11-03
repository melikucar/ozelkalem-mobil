import 'package:flutter/material.dart';

import 'yazi_formatlari.dart';
import 'yerel_db.dart';

/// Arama sonucundaki tek kayıt.
class AramaOgesi {
  const AramaOgesi({required this.yerelId, required this.ad, this.tarih});

  final int yerelId;
  final String ad;

  /// "2026-10-30 14:00:00" ya da null (rehber kişilerinin tarihi yok).
  final String? tarih;
}

/// Sonuçların modül grubu (web ana sayfa arama kutusundaki gruplarla aynı: başlık, simge, vurgu rengi).
class AramaGrubu {
  const AramaGrubu({
    required this.anahtar,
    required this.baslik,
    required this.ikon,
    required this.renk,
    required this.ogeler,
  });

  final String anahtar;
  final String baslik;
  final IconData ikon;
  final Color renk;
  final List<AramaOgesi> ogeler;
}

/// Ana sayfa genel arama: cihazdaki (senkronlanmış) kayıtlarda aynı anda arar; çevrimdışı da çalışır.
/// Web ile aynı kapsam: talepler, telefon rehberi, programlar, randevular, telefon görüşmeleri, faaliyetler, üst yazılar;
/// her grupta en yeni 10 kayıt. Yalnızca kullanıcının yetkisi olan modüller aranır.
class GenelArama {
  GenelArama(this._yerel);

  final YerelDb _yerel;

  static const sinir = 10;

  // anahtar, başlık, ikon, renk, modül yetkisi, sorgu parçaları
  static final _kaynaklar = <_Kaynak>[
    _Kaynak(
      'talepler',
      'Talepler',
      Icons.assignment_ind_outlined,
      const Color(0xFFB4232A),
      'talepler',
      'talepler',
      'talep_eden',
      'tarih',
      ek: ['icerik', 'yapilan_islem', 'referans'],
    ),
    _Kaynak(
      'rehber',
      'Telefon rehberi',
      Icons.menu_book_outlined,
      const Color(0xFF0891B2),
      'telefonlar',
      'kisiler',
      'adi',
      null,
      sirala: 'sira',
    ),
    _Kaynak(
      'programlar',
      'Programlar',
      Icons.calendar_month_outlined,
      const Color(0xFF2563EB),
      'ajanda',
      'programlar',
      'adi',
      'tarih1',
    ),
    _Kaynak(
      'randevular',
      'Randevular',
      Icons.handshake_outlined,
      const Color(0xFF7C3AED),
      'ajanda',
      'randevular',
      'adi',
      'tarih',
    ),
    _Kaynak(
      'gorusmeler',
      'Telefon görüşmeleri',
      Icons.phone_in_talk_outlined,
      const Color(0xFFD97706),
      'telefonlar',
      'gorusmeler',
      'adi',
      't1',
    ),
    _Kaynak(
      'faaliyetler',
      'Faaliyetler',
      Icons.folder_open_outlined,
      const Color(0xFF0F766E),
      'faaliyetler',
      'faaliyetler',
      'adi',
      'tarih',
    ),
    _Kaynak(
      'yazismalar',
      'Üst yazılar',
      Icons.edit_note_rounded,
      const Color(0xFFA16207),
      'yazismalar',
      'yazismalar',
      'kisi',
      'tarih',
    ),
  ];

  /// Aranabilir modül var mı (arama kutusu gösterilsin mi).
  static bool aranabilir(bool Function(String) modulVar) =>
      _kaynaklar.any((k) => modulVar(k.modul));

  Future<List<AramaGrubu>> ara(
    String kelime,
    bool Function(String) modulVar,
  ) async {
    final ham = kelime.trim();
    final norm = aramaMetni(ham);
    if (ham.isEmpty || norm.isEmpty) return [];
    final cikti = <AramaGrubu>[];
    for (final k in _kaynaklar) {
      if (!modulVar(k.modul)) continue;
      final kosul = <String>['ara LIKE ?'];
      final arg = <Object?>['%$norm%'];
      for (final e in k.ek) {
        kosul.add('$e LIKE ?');
        arg.add('%$ham%');
      }
      final sira = k.sirala != null
          ? k.sirala!
          : '${k.tarih} DESC, yerel_id DESC';
      final r = await _yerel.db.rawQuery(
        'SELECT yerel_id, ${k.ad} AS ad${k.tarih == null ? '' : ', ${k.tarih} AS tarih'} '
        'FROM ${k.tablo} WHERE silindi = 0 AND (${kosul.join(' OR ')}) '
        'ORDER BY $sira LIMIT $sinir',
        arg,
      );
      if (r.isEmpty) continue;
      cikti.add(
        AramaGrubu(
          anahtar: k.anahtar,
          baslik: k.baslik,
          ikon: k.ikon,
          renk: k.renk,
          ogeler: [
            for (final x in r)
              AramaOgesi(
                yerelId: x['yerel_id'] as int,
                ad: '${x['ad'] ?? ''}',
                tarih: x['tarih'] as String?,
              ),
          ],
        ),
      );
    }
    return cikti;
  }
}

class _Kaynak {
  _Kaynak(
    this.anahtar,
    this.baslik,
    this.ikon,
    this.renk,
    this.modul,
    this.tablo,
    this.ad,
    this.tarih, {
    this.ek = const [],
    this.sirala,
  });

  final String anahtar;
  final String baslik;
  final IconData ikon;
  final Color renk;
  final String modul;
  final String tablo;
  final String ad;
  final String? tarih;
  final List<String> ek;
  final String? sirala;
}
