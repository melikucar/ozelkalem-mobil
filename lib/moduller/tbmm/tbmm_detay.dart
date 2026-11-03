import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/tbmm.dart';
import '../../veri/tbmm_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../programlar/program_ortak.dart';
import 'tbmm_formu.dart';
import 'tbmm_ortak.dart';

/// Kayıt ayrıntısı: tür, ad, tarih, içerik, bilgi notu, ek dosyalar (görsel / belge açma) ve kayıt bilgileri; PDF çıktısı.
class TbmmDetay extends StatefulWidget {
  const TbmmDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<TbmmDetay> createState() => _TbmmDetayState();
}

class _TbmmDetayState extends State<TbmmDetay> {
  Tbmm? _t;
  KuyrukOp? _sorun;
  List<KuyrukOp> _dosyaIslemleri = [];
  Map<String, dynamic>? _ek;
  TbmmReferans _ref = TbmmReferans({});
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _ekHata = false;
  bool _pdf = false;

  TbmmDeposu get _depo => widget.veri.tbmm;

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
    final t = await _depo.getir(widget.yerelId);
    final s = (await _depo.sorunlular())[widget.yerelId];
    final d = await _depo.dosyaIslemleri(widget.yerelId);
    final ek = t?.no == null ? null : await _depo.ekOku(t!.no!);
    final ref = await _depo.referans();
    if (!mounted) return;
    if (t == null || t.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ilk = !_yuklendi;
    setState(() {
      _t = t;
      _sorun = s;
      _dosyaIslemleri = d;
      _ek = ek;
      _ref = TbmmReferans(ref);
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _t?.no;
    final senk = widget.veri.motor.tbmmSenkron;
    if (no == null || senk == null) return;
    setState(() {
      _ekYukleniyor = true;
      _ekHata = false;
    });
    try {
      final v = await senk.ayrintiGetir(no);
      if (mounted) setState(() => _ek = v);
    } on ApiHata {
      if (mounted) setState(() => _ekHata = true);
    } finally {
      if (mounted) setState(() => _ekYukleniyor = false);
    }
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TbmmFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kayıt silinsin mi?'),
        content: const Text(
          'Kayıt ve ek dosyaları çöp kutusuna taşınır (web panelinden geri alınabilir).',
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

  Future<void> _yazdir() async {
    final no = _t?.no;
    if (no == null) {
      _mesaj(
        'Kayıt henüz sunucuya gönderilmedi; senkron bittikten sonra deneyin.',
      );
      return;
    }
    setState(() => _pdf = true);
    final h = await tbmmPdfAc(
      widget.veri.motor.api,
      'tbmm/pdf?no=$no',
      'tbmm-$no.pdf',
    );
    if (mounted) {
      setState(() => _pdf = false);
      if (h != null) _mesaj(h);
    }
  }

  String _kimNe(Object? b) {
    if (b is! Map) return '—';
    final ad = '${b['adi'] ?? ''}'.trim();
    final z = uzunZaman(b['zaman'] as String?);
    final p = [if (ad.isNotEmpty) ad, ?z];
    return p.isEmpty ? '—' : p.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (!_yuklendi || t == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final renk = tbmmRengi(t.tablo);
    final ek = _ek;
    final dosyalar = [
      for (final x in (ek?['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final api = widget.veri.motor.api;

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
            ikon: tbmmIkonu(t.tablo),
            baslik: 'KAYIT DETAYI',
            altBaslik: tbmmTarihKisa(t.tarih),
            eylemler: [
              if (_ekYukleniyor || _pdf)
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
                tooltip: 'Yazdır (PDF)',
                icon: const Icon(Icons.print_outlined),
                onPressed: _pdf ? null : _yazdir,
              ),
              PopupMenuButton<String>(
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'duzenle') _duzenle();
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
                            baslik: _ref.tabloAdi(t.tablo).isEmpty
                                ? 'Kayıt'
                                : _ref.tabloAdi(t.tablo),
                            ikon: tbmmIkonu(t.tablo),
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.adi.trim().isEmpty ? '(ADSIZ)' : t.adBuyuk,
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    TbmmRozet(
                                      metin: tbmmTarihKisa(t.tarih),
                                      ikon: Icons.event_outlined,
                                    ),
                                    if (_ref.tabloAdi(t.tablo).isNotEmpty)
                                      TbmmRozet(
                                        metin: _ref.tabloAdi(t.tablo),
                                        renk: renk,
                                        ikon: tbmmIkonu(t.tablo),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'İçerik',
                            ikon: Icons.article_outlined,
                            cocuk: SelectableText(
                              t.icerikDuz.trim().isEmpty
                                  ? '—'
                                  : t.icerikDuz.trim(),
                              style: tema.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (t.notlar.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Bilgi notu',
                              ikon: Icons.notes_rounded,
                              cocuk: SelectableText(
                                t.notlar.trim(),
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          if (dosyalar.isNotEmpty ||
                              _dosyaIslemleri.isNotEmpty ||
                              (ek == null && t.no != null))
                            ProgramKutu(
                              baslik: 'Ek dosyalar',
                              ikon: Icons.attach_file_rounded,
                              cocuk: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ek == null && t.no != null)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _ekHata
                                                ? 'Ek dosyalar için bağlantı gerekir.'
                                                : 'Yükleniyor…',
                                            style: tema.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                        if (_ekHata)
                                          TextButton(
                                            onPressed: _ekiYenile,
                                            child: const Text('Yenile'),
                                          ),
                                      ],
                                    ),
                                  for (final d in dosyalar)
                                    DosyaSatiri(
                                      ad: '${d['goruntu']}',
                                      boyut: d['boyut'] as int?,
                                      tikla: () => sunucuDosyasiniAc(
                                        context,
                                        api,
                                        t.no!,
                                        '${d['ad']}',
                                        '${d['goruntu']}',
                                        modul: 'tbmm',
                                      ),
                                    ),
                                  for (final op in _dosyaIslemleri)
                                    DosyaSatiri(
                                      ad: op.tur == 'dosya'
                                          ? '${op.govde['ad']}'
                                          : 'Silinecek: ${op.govde['ad']}',
                                      boyut: op.govde['boyut'] as int?,
                                      etiket: op.durum == 'bekliyor'
                                          ? 'gönderilecek'
                                          : 'hata',
                                      kaldir: () =>
                                          _depo.dosyaIsleminiIptalEt(op),
                                    ),
                                ],
                              ),
                            ),
                          ProgramKutu(
                            baslik: 'Kayıt bilgileri',
                            ikon: Icons.info_outline_rounded,
                            cocuk: ek == null
                                ? Text(
                                    _ekHata
                                        ? 'Kaydeden ve kayıt zamanları için bağlantı gerekir.'
                                        : 'Yükleniyor…',
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  )
                                : Column(
                                    children: [
                                      _Satir(
                                        'Kaydeden',
                                        '${ek['ekleyen'] ?? ''}'.isEmpty
                                            ? _ref.kaydedenAdi(t.ekleyen)
                                            : '${ek['ekleyen']}',
                                      ),
                                      _Satir(
                                        'İlk kayıt',
                                        _kimNe(ek['ilk_kayit']),
                                      ),
                                      _Satir(
                                        'Son güncelleme',
                                        _kimNe(ek['son_guncelleme']),
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
  final TbmmDeposu depo;
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
                        ? 'Bu kayıt siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
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
