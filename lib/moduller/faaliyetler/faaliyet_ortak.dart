import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../veri/faaliyet.dart';
import '../../veri/faaliyet_deposu.dart';
import '../../veri/yazi_formatlari.dart';
import '../programlar/program_ortak.dart';

/// Sunucudan gelen faaliyet referansı (kategori, yer, kaydedenler, kitapçık şablonları).
class FaaliyetReferans {
  FaaliyetReferans(this.v);

  final Map<String, dynamic> v;

  bool get bos => v.isEmpty;

  List<Map<String, dynamic>> _liste(String k) => [
    for (final x in (v[k] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  List<Map<String, dynamic>> get kategoriler => _liste('kategoriler');
  List<Map<String, dynamic>> get yerler => _liste('yerler');
  List<Map<String, dynamic>> get kaydedenler => _liste('kaydedenler');

  String _ad(List<Map<String, dynamic>> l, int no) {
    for (final k in l) {
      if (k['no'] == no) return '${k['adi']}';
    }
    return '';
  }

  String kategoriAdi(int no) => _ad(kategoriler, no);
  String yerAdi(int no) => _ad(yerler, no);
  String kaydedenAdi(int no) => _ad(kaydedenler, no);
}

/// Web listesindeki gibi kategori başına sabit vurgu rengi.
Color kategoriRengi(int katno, {bool koyu = false}) => HSLColor.fromAHSL(
  1,
  ((katno * 47) % 360).toDouble(),
  0.62,
  koyu ? 0.62 : 0.42,
).toColor();

/// Faaliyet küçük resimleri: bellekte tutulur, aynı anda en çok 3 istek gider.
class FaaliyetGorselleri {
  FaaliyetGorselleri._();

  static final _bellek = <String, Uint8List?>{};
  static final _bekleyen = <String, Future<Uint8List?>>{};
  static int _calisan = 0;
  static final _sira = <Completer<void>>[];

  static Future<void> _yer() async {
    if (_calisan < 3) {
      _calisan++;
      return;
    }
    final c = Completer<void>();
    _sira.add(c);
    await c.future;
  }

  static void _birak() {
    if (_sira.isNotEmpty) {
      _sira.removeAt(0).complete();
    } else {
      _calisan--;
    }
  }

  /// null: görsel yok (404) ya da alınamadı.
  static Future<Uint8List?> getir(ApiIstemci api, String yol) {
    if (_bellek.containsKey(yol)) return Future.value(_bellek[yol]);
    return _bekleyen[yol] ??= () async {
      await _yer();
      try {
        final b = await api.indir(yol);
        _bellek[yol] = b;
        return b;
      } on ApiHata catch (e) {
        if (e.durum == 404) _bellek[yol] = null;
        return null;
      } finally {
        _birak();
        _bekleyen.remove(yol);
      }
    }();
  }

  static void temizle() => _bellek.clear();
}

/// Listedeki küçük resim: önce yerel "resim var mı" durumuna bakar; yoksa kategori renginde ikon gösterir.
class FaaliyetKucukResim extends StatefulWidget {
  const FaaliyetKucukResim({
    super.key,
    required this.faaliyet,
    required this.api,
    required this.depo,
    this.boy = 64,
  });

  final Faaliyet faaliyet;
  final ApiIstemci api;
  final FaaliyetDeposu depo;
  final double boy;

  @override
  State<FaaliyetKucukResim> createState() => _FaaliyetKucukResimState();
}

class _FaaliyetKucukResimState extends State<FaaliyetKucukResim> {
  Uint8List? _bayt;
  late int _durum = widget.faaliyet.resimDurumu;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final f = widget.faaliyet;
    if (f.no == null || _durum == 2) return;
    final b = await FaaliyetGorselleri.getir(
      widget.api,
      'faaliyetler/resim?no=${f.no}',
    );
    if (!mounted) return;
    final yeni = b == null ? 2 : 1;
    if (yeni != _durum && f.yerelId != null) {
      widget.depo.resimDurumuYaz(f.yerelId!, yeni);
    }
    setState(() {
      _bayt = b;
      _durum = yeni;
    });
  }

  @override
  Widget build(BuildContext context) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final renk = kategoriRengi(widget.faaliyet.katno, koyu: koyu);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: widget.boy,
        height: widget.boy,
        child: _bayt != null
            ? Image.memory(
                _bayt!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _bos(renk),
              )
            : _bos(renk),
      ),
    );
  }

  Widget _bos(Color renk) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [renk.withValues(alpha: 0.28), renk.withValues(alpha: 0.12)],
      ),
    ),
    child: Icon(Icons.campaign_outlined, color: renk, size: widget.boy * 0.42),
  );
}

/// Liste kartı: küçük resim, ad, tarih, kategori ve yer rozetleri, kaydeden; bekleyen / sorunlu işaretleri.
class FaaliyetKarti extends StatelessWidget {
  const FaaliyetKarti({
    super.key,
    required this.faaliyet,
    required this.ref,
    required this.api,
    required this.depo,
    required this.tikla,
    this.sorunlu = false,
  });

  final Faaliyet faaliyet;
  final FaaliyetReferans ref;
  final ApiIstemci api;
  final FaaliyetDeposu depo;
  final VoidCallback tikla;
  final bool sorunlu;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final f = faaliyet;
    final koyu = tema.brightness == Brightness.dark;
    final renk = kategoriRengi(f.katno, koyu: koyu);
    final kat = ref.kategoriAdi(f.katno);
    final yer = ref.yerAdi(f.yer);
    final ozet = f.icerikDuz.replaceAll('\n', ' ');
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: programGolgesi(context),
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tikla,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: renk),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FaaliyetKucukResim(
                          faaliyet: f,
                          api: api,
                          depo: depo,
                          boy: 68,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    uzunTarihSade(f.tarih),
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (sorunlu)
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 16,
                                      color: Color(0xFFE11D48),
                                    )
                                  else if (f.bekleyen)
                                    Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                f.adBuyuk,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                              if (ozet.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  ozet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (kat.isNotEmpty)
                                    _Rozet(metin: kat, renk: renk, nokta: true),
                                  if (yer.isNotEmpty)
                                    _Rozet(
                                      metin: yer,
                                      ikon: Icons.place_outlined,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rozet extends StatelessWidget {
  const _Rozet({required this.metin, this.renk, this.ikon, this.nokta = false});

  final String metin;
  final Color? renk;
  final IconData? ikon;
  final bool nokta;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = renk ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (renk ?? cs.onSurfaceVariant).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nokta)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          if (ikon != null) ...[
            Icon(ikon, size: 12, color: c),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              metin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "30 Eki 2026" biçimi.
String uzunTarihSade(DateTime d) =>
    '${d.day} ${trAylarKisa[d.month]} ${d.year}';

/// Başlık satırında kullanılan büyük harfli ad (boşsa "(adsız)").
String faaliyetBasligi(String adi) =>
    adi.trim().isEmpty ? '(ADSIZ)' : trBuyuk(adi);
