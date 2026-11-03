import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../api/api_istemci.dart';
import '../../api/oturum.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/yazisma.dart';
import '../../veri/yazisma_deposu.dart';
import '../programlar/program_ortak.dart';
import 'yazisma_formu.dart';
import 'yazisma_gonder.dart';
import 'yazisma_ortak.dart';

/// Yazı ayrıntısı: A4 önizleme, PDF / Word, WhatsApp ve e-posta ile gönderme, ilgili kişi, kayıt bilgileri.
class YazismaDetay extends StatefulWidget {
  const YazismaDetay({
    super.key,
    required this.veri,
    required this.oturum,
    required this.yerelId,
  });

  final VeriKatmani veri;
  final Oturum oturum;
  final int yerelId;

  @override
  State<YazismaDetay> createState() => _YazismaDetayState();
}

class _YazismaDetayState extends State<YazismaDetay> {
  Yazisma? _y;
  KuyrukOp? _sorun;
  Map<String, dynamic>? _ek;
  YazismaReferans _ref = YazismaReferans({});
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _islem = false;

  YazismaDeposu get _depo => widget.veri.yazismalar;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yukle);
    _yukle();
  }

  @override
  void dispose() {
    _depo.removeListener(_yukle);
    super.dispose();
  }

  Future<void> _yukle() async {
    final y = await _depo.getir(widget.yerelId);
    final s = (await _depo.sorunlular())[widget.yerelId];
    final ek = y?.no == null ? null : await _depo.ekOku(y!.no!);
    final ref = await _depo.referans();
    if (!mounted) return;
    if (y == null || y.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ilk = !_yuklendi;
    setState(() {
      _y = y;
      _sorun = s;
      _ek = ek;
      _ref = YazismaReferans(ref);
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _y?.no;
    final senk = widget.veri.motor.yazismaSenkron;
    if (no == null || senk == null) return;
    setState(() => _ekYukleniyor = true);
    try {
      final v = await senk.ayrintiGetir(no);
      if (mounted) setState(() => _ek = v);
    } on ApiHata {
      // çevrimdışı: önbellekteki bilgi gösterilir
    } finally {
      if (mounted) setState(() => _ekYukleniyor = false);
    }
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => YazismaFormu(
        veri: widget.veri,
        oturum: widget.oturum,
        yerelId: widget.yerelId,
      ),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Yazı silinsin mi?'),
        content: const Text(
          'Yazı çöp kutusuna taşınır (web panelinden geri alınabilir).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    await _depo.sil(widget.yerelId);
    if (mounted) Navigator.of(context).pop();
  }

  /// Yazıyı sunucudan PDF / Word olarak indirip cihazdaki uygulamayla açar (oradan paylaşılabilir).
  Future<void> _dosyaAc(String tur) async {
    final no = _y?.no;
    if (no == null) {
      _mesaj(
        'Yazı henüz sunucuya gönderilmedi; senkron bittikten sonra deneyin.',
      );
      return;
    }
    setState(() => _islem = true);
    try {
      final r = await widget.veri.motor.api.dosyaIndir(
        'yazismalar/dosya?no=$no&tur=$tur',
      );
      final dizin = Directory(
        p.join((await getTemporaryDirectory()).path, 'yazilar'),
      );
      if (!dizin.existsSync()) dizin.createSync(recursive: true);
      final ad = _dosyaAdi(tur == 'word' ? 'docx' : 'pdf');
      final yol = p.join(dizin.path, ad);
      await File(yol).writeAsBytes(r.bayt, flush: true);
      final s = await OpenFilex.open(yol);
      if (s.type != ResultType.done && mounted) {
        _mesaj(
          s.type == ResultType.noAppToOpen
              ? 'Bu dosyayı açabilecek uygulama yok.'
              : 'Dosya açılamadı.',
        );
      }
    } on ApiHata catch (e) {
      _mesaj(
        e.agHatasi ? 'PDF / Word için internet bağlantısı gerekir.' : e.mesaj,
      );
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  String _dosyaAdi(String uzanti) {
    final k = (_y?.kisi ?? '')
        .replaceAll(RegExp(r'[^\p{L}\p{N} ._-]', unicode: true), '')
        .trim();
    return 'Yazışma - ${k.isEmpty ? 'yazı' : k}.$uzanti';
  }

  String get _duzMetin {
    final y = _y!;
    return [
      'Sayın ${y.kisi}',
      if (y.unvan.isNotEmpty) y.unvan,
      '',
      y.icerikDuz.trim(),
    ].join('\n');
  }

  Future<void> _gonder() async {
    final y = _y!;
    await YazismaGonder.goster(
      context,
      yazisma: y,
      ref: _ref,
      motor: widget.veri.motor,
      duzMetin: _duzMetin,
      pdfAc: () => _dosyaAc('pdf'),
      wordAc: () => _dosyaAc('word'),
      mesaj: _mesaj,
    );
  }

  Future<void> _kopyala() async {
    await Clipboard.setData(ClipboardData(text: _duzMetin));
    _mesaj('Yazı metni kopyalandı.');
  }

  String _kimNe(Object? b) {
    if (b is! Map) return '—';
    final ad = '${b['adi'] ?? ''}'.trim();
    final z = uzunZaman(b['zaman'] as String?);
    final pr = [if (ad.isNotEmpty) ad, ?z];
    return pr.isEmpty ? '—' : pr.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final y = _y;
    if (!_yuklendi || y == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final renk = yazismaRengi(y.kisi, koyu: !acik);
    final ekleyen = _ek?['ekleyen']?.toString().trim().isNotEmpty == true
        ? _ek!['ekleyen'].toString()
        : _ref.kaydedenAdi(y.ekleyen);

    return Scaffold(
      floatingActionButton: KompaktDugme(
        ikon: Icons.edit_outlined,
        etiket: _sorun?.durum == 'cakisma' ? 'Çakışmayı çöz' : 'Düzenle',
        onPressed: _duzenle,
      ),
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.mail_outline_rounded,
            baslik: 'YAZI DETAYI',
            altBaslik: yazismaTarihYaz(y.tarih),
            eylemler: [
              if (_ekYukleniyor || _islem)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Gönder / paylaş',
                icon: const Icon(Icons.send_rounded),
                onPressed: _islem ? null : _gonder,
              ),
              PopupMenuButton<String>(
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'duzenle') _duzenle();
                  if (v == 'pdf') _dosyaAc('pdf');
                  if (v == 'word') _dosyaAc('word');
                  if (v == 'kopyala') _kopyala();
                  if (v == 'yenile') _ekiYenile();
                  if (v == 'sil') _sil();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'duzenle',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Düzenle'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pdf',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('PDF olarak aç'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'word',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined),
                      title: Text('Word olarak aç'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'kopyala',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.copy_rounded),
                      title: Text('Metni kopyala'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'yenile',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh_rounded),
                      title: Text('Ayrıntıları yenile'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sil',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Sil'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.3, 1],
                ),
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_sorun != null)
                            _SorunSeridi(
                              op: _sorun!,
                              depo: _depo,
                              motor: widget.veri.motor,
                            ),
                          ProgramKutu(
                            baslik: 'Yazı',
                            ikon: Icons.mail_outline_rounded,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  y.kisi.isEmpty
                                      ? '(MUHATAP YOK)'
                                      : y.kisiBuyuk,
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                if (y.unvan.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      y.unvan,
                                      style: tema.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _Etiket(
                                      ikon: Icons.event_outlined,
                                      metin: yazismaTarihYaz(y.tarih),
                                    ),
                                    if (y.ilgili.isNotEmpty)
                                      _Etiket(
                                        ikon: y.talepBagli
                                            ? Icons.assignment_ind_outlined
                                            : Icons.person_outline_rounded,
                                        metin: trBuyuk(y.ilgili),
                                        renk: renk,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'A4 önizleme',
                            ikon: Icons.preview_outlined,
                            cocuk: YazismaKagidi(
                              kisi: y.kisi,
                              unvan: y.unvan,
                              metin: y.icerikDuz,
                              logo: y.logo,
                              imza: y.imza,
                              imzaUnvan: y.imzaUnvan,
                              imzaUnvan2: y.imzaUnvan2,
                              altYazi: y.altYazi,
                              makamLogo: widget.oturum.makamResmi,
                              makamImza: widget.oturum.makamImza,
                              makam:
                                  widget.oturum.ben?['makam']
                                      as Map<String, dynamic>?,
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Kayıt bilgisi',
                            ikon: Icons.info_outline_rounded,
                            cocuk: Column(
                              children: [
                                _Satir('Kaydeden', ekleyen),
                                _Satir('İlk kayıt', _kimNe(_ek?['ilk_kayit'])),
                                _Satir(
                                  'Son güncelleme',
                                  _kimNe(_ek?['son_guncelleme']),
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
        ],
      ),
    );
  }
}

class _Etiket extends StatelessWidget {
  const _Etiket({required this.ikon, required this.metin, this.renk});

  final IconData ikon;
  final String metin;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = renk ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 14, color: c),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              metin,
              style: TextStyle(
                fontSize: 12,
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

class _Satir extends StatelessWidget {
  const _Satir(this.etiket, this.deger);

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              etiket,
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              deger.isEmpty ? '—' : deger,
              style: tema.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SorunSeridi extends StatelessWidget {
  const _SorunSeridi({
    required this.op,
    required this.depo,
    required this.motor,
  });

  final KuyrukOp op;
  final YazismaDeposu depo;
  final dynamic motor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cakisma = op.durum == 'cakisma';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cakisma
              ? tema.colorScheme.tertiaryContainer
              : tema.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  cakisma ? Icons.warning_amber_rounded : Icons.error_outline,
                  color: cakisma
                      ? Colors.amber.shade900
                      : tema.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cakisma
                        ? 'Bu yazı siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
                        : 'Son değişiklik gönderilemedi: ${op.mesaj}',
                    style: tema.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (cakisma) ...[
                  FilledButton.tonal(
                    onPressed: () async {
                      await depo.cakismaBenimkiniGonder(op);
                      motor.senkronla();
                    },
                    child: const Text('Benimkini koru'),
                  ),
                  OutlinedButton(
                    onPressed: () => depo.cakismaSunucuyuAl(op),
                    child: const Text('Sunucudakini al'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () => depo.islemiIptalEt(op),
                    child: const Text('Değişikliği geri al'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
