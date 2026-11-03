import 'dart:async';

import 'package:flutter/material.dart';

import '../api/oturum.dart';
import '../moduller/faaliyetler/faaliyet_detay.dart';
import '../moduller/programlar/program_detay.dart';
import '../moduller/programlar/program_ortak.dart';
import '../moduller/randevular/randevu_detay.dart';
import '../moduller/talepler/talep_detay.dart';
import '../moduller/telefonRehberi/gorusme_detay.dart';
import '../moduller/telefonRehberi/kisi_detay.dart';
import '../moduller/yazismalar/yazisma_detay.dart';
import '../veri/genel_arama.dart';
import '../veri/veri_katmani.dart';
import '../veri/yazi_formatlari.dart';

/// Ana sayfa genel arama kutusu (web başlığındaki arama kutusunun mobil karşılığı): yazdıkça sonuçlar modüllere göre gruplanır,
/// her grupta en yeni 10 kayıt görünür; bir kayda dokununca ayrıntısı açılır. Cihazdaki kayıtlarda aradığı için çevrimdışı da çalışır.
class AnaArama extends StatefulWidget {
  const AnaArama({
    super.key,
    required this.oturum,
    required this.veri,
    this.sonucDegisti,
  });

  /// Sonuç alanı açıldı/kapandı (ana sayfa çevreyi bulanıklaştırır).
  final ValueChanged<bool>? sonucDegisti;

  final Oturum oturum;
  final VeriKatmani veri;

  @override
  State<AnaArama> createState() => AnaAramaState();
}

class AnaAramaState extends State<AnaArama> {
  bool _sonAktif = false;
  final _girdi = TextEditingController();
  final _odak = FocusNode();
  late final GenelArama _arama = GenelArama(widget.veri.yerel);
  Timer? _bekle;
  int _istek = 0;
  List<AramaGrubu>? _sonuc;
  String? _tab; // seçili sonuç sekmesi (grup anahtarı)
  bool _araniyor = false;
  bool _cihazBos =
      false; // kayıtlar henüz cihaza inmedi (ilk yükleme sürüyor / cihaz boş)

  @override
  void dispose() {
    _bekle?.cancel();
    _girdi.dispose();
    _odak.dispose();
    super.dispose();
  }

  void _degisti(String v) {
    _bekle?.cancel();
    setState(() {});
    if (v.trim().isEmpty) {
      _istek++;
      setState(() {
        _sonuc = null;
        _araniyor = false;
      });
      return;
    }
    _bekle = Timer(const Duration(milliseconds: 250), _calistir);
  }

  Future<void> _calistir() async {
    final no = ++_istek;
    setState(() => _araniyor = true);
    final s = await _arama.ara(_girdi.text, widget.oturum.modulVar);
    var bos = false;
    if (s.isEmpty) {
      final m = widget.veri.motor;
      bos = m.ilkYukleme || (await m.kayitSayaci?.call() ?? 1) == 0;
    }
    if (!mounted || no != _istek) return;
    setState(() {
      _cihazBos = bos;
      _sonuc = s;
      _araniyor = false;
      if (!s.any((g) => g.anahtar == _tab)) {
        _tab = s.isEmpty ? null : s.first.anahtar;
      }
    });
  }

  /// Aramayı temizler ve sonuç alanını kapatır.
  void kapat() => _kapat();

  void _kapat() {
    _bekle?.cancel();
    _istek++;
    _girdi.clear();
    _odak.unfocus();
    setState(() {
      _sonuc = null;
      _tab = null;
      _araniyor = false;
    });
  }

  Future<void> _ac(AramaGrubu g, AramaOgesi o) {
    final veri = widget.veri;
    final Widget sayfa = switch (g.anahtar) {
      'talepler' => TalepDetay(veri: veri, yerelId: o.yerelId),
      'rehber' => KisiDetay(veri: veri, yerelId: o.yerelId),
      'programlar' => ProgramDetay(veri: veri, yerelId: o.yerelId),
      'randevular' => RandevuDetay(veri: veri, yerelId: o.yerelId),
      'gorusmeler' => GorusmeDetay(veri: veri, yerelId: o.yerelId),
      'faaliyetler' => FaaliyetDetay(veri: veri, yerelId: o.yerelId),
      _ => YazismaDetay(veri: veri, oturum: widget.oturum, yerelId: o.yerelId),
    };
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => sayfa));
  }

  String _tarih(String? t) {
    if (t == null || t.length < 10) return '';
    final p = t.substring(0, 10).split('-');
    if (p.length != 3) return '';
    return '${p[2]}.${p[1]}.${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final sonuc = _sonuc;
    final aktif = sonuc != null;
    if (aktif != _sonAktif) {
      _sonAktif = aktif;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.sonucDegisti?.call(aktif),
      );
    }
    final toplam = sonuc?.fold<int>(0, (a, g) => a + g.ogeler.length) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: programGolgesi(context),
            ),
            child: Material(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              child: TextField(
                style: const TextStyle(fontSize: 14),
                controller: _girdi,
                focusNode: _odak,
                onChanged: _degisti,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _calistir(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Aranacak kelimeyi giriniz',
                  hintStyle: const TextStyle(fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 42,
                    minHeight: 38,
                  ),
                  suffixIcon: _araniyor
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_girdi.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Aramayı temizle',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: _kapat,
                              )),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),
          if (sonuc != null) ...[
            const SizedBox(height: 10),
            if (sonuc.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: programGolgesi(context),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.sentiment_dissatisfied_outlined,
                      size: 34,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cihazBos
                          ? 'Kayıtlar henüz cihaza indirilmedi'
                          : 'Sonuç bulunamadı',
                      style: tema.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _cihazBos
                          ? 'İlk yükleme sürüyor ya da cihazda kayıt yok. Bağlantıyı kontrol edip sayfayı aşağı çekerek eşitleyin, sonra tekrar arayın.'
                          : 'Aradığınız kelimeye uygun kayıt yok. Farklı bir kelimeyle deneyin.',
                      textAlign: TextAlign.center,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$toplam',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const TextSpan(text: ' sonuç bulundu'),
                          ],
                        ),
                        style: tema.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: _kapat,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
              ),
              _sonucAlani(sonuc, tema, cs),
            ],
          ],
        ],
      ),
    );
  }

  /// Tek bir alan: üstte modül sekmeleri (simge, ad, sayı), altında seçili modülün sonuçları.
  Widget _sonucAlani(List<AramaGrubu> sonuc, ThemeData tema, ColorScheme cs) {
    final g = sonuc.firstWhere(
      (x) => x.anahtar == _tab,
      orElse: () => sonuc.first,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: programGolgesi(context),
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                children: [
                  for (final t in sonuc)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        showCheckmark: false,
                        avatar: Icon(
                          t.ikon,
                          size: 16,
                          color: t.anahtar == g.anahtar ? t.renk : null,
                        ),
                        label: Text('${t.baslik}  ${t.ogeler.length}'),
                        selected: t.anahtar == g.anahtar,
                        selectedColor: t.renk.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          fontWeight: t.anahtar == g.anahtar
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: t.anahtar == g.anahtar ? t.renk : null,
                        ),
                        onSelected: (_) => setState(() => _tab = t.anahtar),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 2, color: g.renk.withValues(alpha: 0.5)),
            for (final o in g.ogeler)
              InkWell(
                onTap: () => _ac(g, o),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      if (_tarih(o.tarih).isNotEmpty)
                        SizedBox(
                          width: 78,
                          child: Text(
                            _tarih(o.tarih),
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          o.ad.trim().isEmpty
                              ? '(ADSIZ)'
                              : trBuyuk(o.ad.trim()),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
