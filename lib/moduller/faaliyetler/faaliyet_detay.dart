import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_istemci.dart';
import '../../veri/faaliyet.dart';
import '../../veri/faaliyet_deposu.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'faaliyet_formu.dart';
import 'faaliyet_ortak.dart';
import 'gorsel_gezgin.dart';

/// Faaliyet ayrıntısı: kategori / yer / tarih, içerik, bilgi notu, haber bağlantıları, fotoğraf galerisi, diğer ekler ve kayıt bilgileri.
class FaaliyetDetay extends StatefulWidget {
  const FaaliyetDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<FaaliyetDetay> createState() => _FaaliyetDetayState();
}

class _FaaliyetDetayState extends State<FaaliyetDetay> {
  Faaliyet? _f;
  KuyrukOp? _sorun;
  List<KuyrukOp> _dosyaIslemleri = [];
  Map<String, dynamic>? _ek;
  FaaliyetReferans _ref = FaaliyetReferans({});
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _ekHata = false;

  FaaliyetDeposu get _depo => widget.veri.faaliyetler;

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
    final f = await _depo.getir(widget.yerelId);
    final s = (await _depo.sorunlular())[widget.yerelId];
    final d = await _depo.dosyaIslemleri(widget.yerelId);
    final ek = f?.no == null ? null : await _depo.ekOku(f!.no!);
    final ref = await _depo.referans();
    if (!mounted) return;
    if (f == null || f.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ilk = !_yuklendi;
    setState(() {
      _f = f;
      _sorun = s;
      _dosyaIslemleri = d;
      _ek = ek;
      _ref = FaaliyetReferans(ref);
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _f?.no;
    final senk = widget.veri.motor.faaliyetSenkron;
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
      builder: (_) => FaaliyetFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Faaliyet silinsin mi?'),
        content: const Text(
          'Faaliyet ve ek dosyaları çöp kutusuna taşınır (web panelinden geri alınabilir).',
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

  Future<void> _baglantiAc(String url) async {
    var u = url.trim();
    if (!RegExp(r'^[a-z]+://', caseSensitive: false).hasMatch(u)) {
      u = 'https://$u';
    }
    final tamam = await launchUrl(
      Uri.parse(u),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!tamam && mounted) _mesaj('Bağlantı açılamadı.');
  }

  String _kimNe(Object? b) {
    if (b is! Map) return '—';
    final ad = '${b['adi'] ?? ''}'.trim();
    final z = uzunZaman(b['zaman'] as String?);
    final p = [if (ad.isNotEmpty) ad, ?z];
    return p.isEmpty ? '—' : p.join(' · ');
  }

  bool _resimMi(Map<String, dynamic> d) => const {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'jfif',
  }.contains('${d['tur']}'.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final f = _f;
    if (!_yuklendi || f == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final koyu = !acik;
    final renk = kategoriRengi(f.katno, koyu: koyu);
    final ek = _ek;
    final dosyalar = [
      for (final x in (ek?['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final resimler = dosyalar.where(_resimMi).toList();
    final digerleri = dosyalar.where((d) => !_resimMi(d)).toList();
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
            ikon: Icons.campaign_outlined,
            baslik: 'FAALİYET DETAYI',
            altBaslik: uzunGunYaz(f.tarih),
            eylemler: [
              if (_ekYukleniyor)
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
                            baslik: 'Faaliyet',
                            ikon: Icons.campaign_outlined,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  faaliyetBasligi(f.adi),
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
                                    if (_ref.kategoriAdi(f.katno).isNotEmpty)
                                      _Etiket(
                                        ikon: Icons.category_outlined,
                                        metin: _ref.kategoriAdi(f.katno),
                                        renk: renk,
                                      ),
                                    if (_ref.yerAdi(f.yer).isNotEmpty)
                                      _Etiket(
                                        ikon: Icons.place_outlined,
                                        metin: _ref.yerAdi(f.yer),
                                      ),
                                    _Etiket(
                                      ikon: Icons.schedule_rounded,
                                      metin:
                                          '${f.tarih.day} ${trAylarKisa[f.tarih.month]} ${f.tarih.year} · ${saatYaz(f.tarih)}',
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
                              f.icerikDuz.trim().isEmpty
                                  ? '—'
                                  : f.icerikDuz.trim(),
                              style: tema.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (f.notlarDuz.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Bilgi notu',
                              ikon: Icons.notes_rounded,
                              cocuk: SelectableText(
                                f.notlarDuz.trim(),
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          if (f.haberler.isNotEmpty)
                            ProgramKutu(
                              baslik: 'Haber / bağlantı',
                              ikon: Icons.link_rounded,
                              cocuk: Column(
                                children: [
                                  for (final h in f.haberler)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _baglantiAc(h),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.open_in_new_rounded,
                                              size: 18,
                                              color: cs.primary,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                h,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: cs.primary,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (ek == null && f.no != null && !_ekYukleniyor)
                            ProgramKutu(
                              baslik: 'Fotoğraf ve ekler',
                              ikon: Icons.attach_file_rounded,
                              cocuk: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _ekHata
                                          ? 'Fotoğraflar ve dosyalar için bağlantı gerekir.'
                                          : 'Yükleniyor…',
                                      style: tema.textTheme.bodySmall?.copyWith(
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
                            ),
                          if (resimler.isNotEmpty)
                            ProgramKutu(
                              baslik: 'Fotoğraflar',
                              ikon: Icons.photo_library_outlined,
                              sag: Text(
                                '${resimler.length}',
                                style: tema.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              cocuk: GridView.count(
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  for (var i = 0; i < resimler.length; i++)
                                    _Galeri(
                                      api: api,
                                      no: f.no!,
                                      dosya: resimler[i],
                                      ac: () => gorselGezginiAc(
                                        context,
                                        api: api,
                                        no: f.no!,
                                        resimler: resimler,
                                        ilk: i,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (digerleri.isNotEmpty ||
                              _dosyaIslemleri.isNotEmpty)
                            ProgramKutu(
                              baslik: 'Ek dosyalar',
                              ikon: Icons.attach_file_rounded,
                              cocuk: Column(
                                children: [
                                  for (final d in digerleri)
                                    DosyaSatiri(
                                      ad: '${d['goruntu']}',
                                      boyut: d['boyut'] as int?,
                                      tikla: () => sunucuDosyasiniAc(
                                        context,
                                        api,
                                        f.no!,
                                        '${d['ad']}',
                                        '${d['goruntu']}',
                                        modul: 'faaliyetler',
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
                                            ? _ref.kaydedenAdi(f.ekleyen)
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

class _Galeri extends StatelessWidget {
  const _Galeri({
    required this.api,
    required this.no,
    required this.dosya,
    required this.ac,
  });

  final ApiIstemci api;
  final int no;
  final Map<String, dynamic> dosya;
  final VoidCallback ac;

  @override
  Widget build(BuildContext context) {
    final yol =
        'faaliyetler/dosya?no=$no&ad=${Uri.encodeQueryComponent('${dosya['ad']}')}&kucuk=1';
    return GestureDetector(
      onTap: ac,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Uint8List?>(
          future: FaaliyetGorselleri.getir(api, yol),
          builder: (c, s) {
            if (s.data != null) {
              return Image.memory(s.data!, fit: BoxFit.cover);
            }
            return ColoredBox(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.08),
              child: Center(
                child: s.connectionState == ConnectionState.done
                    ? const Icon(Icons.broken_image_outlined)
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            );
          },
        ),
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
  final FaaliyetDeposu depo;
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
                        ? 'Bu faaliyet siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
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
