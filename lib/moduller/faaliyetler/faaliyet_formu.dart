import 'dart:io';

import 'package:flutter/material.dart';

import '../../veri/faaliyet.dart';
import '../../veri/faaliyet_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'faaliyet_ortak.dart';

/// Yeni faaliyet / düzenleme (web "Faaliyet Ekle / Düzenle" sayfasının karşılığı): ad, kategori, yer, tarih-saat, içerik,
/// bilgi notu, haber bağlantıları ve ek dosyalar (kameradan fotoğraf dahil). Kayıt önce cihaza yazılır.
class FaaliyetFormu extends StatefulWidget {
  const FaaliyetFormu({super.key, required this.veri, this.yerelId});

  final VeriKatmani veri;

  /// Doluysa düzenleme, boşsa yeni faaliyet.
  final int? yerelId;

  @override
  State<FaaliyetFormu> createState() => _FaaliyetFormuState();
}

class _FaaliyetFormuState extends State<FaaliyetFormu> {
  final _form = GlobalKey<FormState>();
  final _adi = TextEditingController();
  final _icerik = TextEditingController();
  final _notlar = TextEditingController();
  final _haberler = TextEditingController();

  late DateTime _tarih;
  int _katno = 0;
  int _yer = 0;

  Faaliyet? _faaliyet;
  FaaliyetReferans _ref = FaaliyetReferans({});
  Map<String, dynamic>? _ek;
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;
  String _ilkIcerik = '';
  String _ilkNotlar = '';
  final List<SecilenDosya> _yeniDosyalar = [];
  final Set<String> _silinecekDosyalar = {};

  FaaliyetDeposu get _depo => widget.veri.faaliyetler;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _tarih = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    _yukle();
  }

  @override
  void dispose() {
    for (final c in [_adi, _icerik, _notlar, _haberler]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final ref = FaaliyetReferans(await _depo.referans());
    Faaliyet? f;
    Map<String, dynamic>? ek;
    if (!_yeni) {
      f = await _depo.getir(widget.yerelId!);
      if (f?.no != null) ek = await _depo.ekOku(f!.no!);
    }
    if (!mounted) return;
    setState(() {
      _ref = ref;
      _faaliyet = f;
      _ek = ek;
      if (f != null) {
        _adi.text = f.adi;
        _ilkIcerik = f.icerikDuz.trim();
        _ilkNotlar = f.notlarDuz.trim();
        _icerik.text = _ilkIcerik;
        _notlar.text = _ilkNotlar;
        _haberler.text = f.s('haberler').replaceAll('@', '\n');
        _tarih = f.tarih;
        _katno = f.katno;
        _yer = f.yer;
      }
      _hazir = true;
    });
  }

  Future<void> _zamanSec() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _tarih.hour, minute: _tarih.minute),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: w!,
      ),
    );
    if (t == null) return;
    setState(() => _tarih = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    if (!_form.currentState!.validate()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Kırmızı işaretli zorunlu alanları doldurun.'),
          ),
        );
      return;
    }
    if (_katno == 0 || _yer == 0) {
      setState(() => _hata = 'Kategori ve yer seçin.');
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final haberler = _haberler.text
          .split(RegExp(r'[\n@]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join('@');
      final icerik = _icerik.text.trim();
      final notlar = _notlar.text.trim();
      final id = await _depo.kaydet({
        'adi': _adi.text.trim(),
        'katno': _katno,
        'yer': _yer,
        'tarih': faaliyetZamanYaz(_tarih),
        'haberler': haberler,
        // biçimli (kalın, liste…) mevcut içerik yalnızca metin değiştiyse yeniden yazılır
        if (_yeni || icerik != _ilkIcerik) 'icerik': icerik,
        if (_yeni ? notlar.isNotEmpty : notlar != _ilkNotlar) 'notlar': notlar,
      }, yerelId: widget.yerelId);
      for (final d in _yeniDosyalar) {
        await _depo.dosyaEkle(id, yol: d.yol, ad: d.ad, boyut: d.boyut);
      }
      final no = _faaliyet?.no;
      if (no != null) {
        for (final ad in _silinecekDosyalar) {
          await _depo.sunucuDosyasiniSil(id, no, ad);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _kaydediliyor = false;
          _hata = 'Kaydedilemedi: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(
      zemin,
      tema.colorScheme.primary,
      acik ? 0.10 : 0.14,
    )!;
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.campaign_outlined,
            baslik: _yeni ? 'YENİ FAALİYET' : 'FAALİYETİ DÜZENLE',
            altBaslik: uzunGunYaz(_tarih),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.25, 1],
                ),
              ),
              child: !_hazir
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _form,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 600),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _icerikWidgetlari(tema),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          if (_hazir) _altCubuk(tema),
        ],
      ),
    );
  }

  Widget _altCubuk(ThemeData tema) => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      10,
      16,
      10 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: tema.colorScheme.surface,
      border: Border(top: BorderSide(color: tema.colorScheme.outlineVariant)),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: _kaydediliyor ? null : _kaydet,
            icon: _kaydediliyor
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_yeni ? 'Faaliyeti kaydet' : 'Değişiklikleri kaydet'),
          ),
        ),
      ),
    ),
  );

  List<Widget> _icerikWidgetlari(ThemeData tema) {
    final cs = tema.colorScheme;
    final sunucu = [
      for (final x in (_ek?['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ].where((d) => !_silinecekDosyalar.contains(d['ad'])).toList();
    return [
      ProgramKutu(
        baslik: 'Faaliyet',
        ikon: Icons.campaign_outlined,
        cocuk: Column(
          children: [
            TextFormField(
              controller: _adi,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Faaliyet adı *',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Faaliyet adı zorunludur'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _ref.kategoriler.any((k) => k['no'] == _katno)
                  ? _katno
                  : null,
              isExpanded: true,
              hint: const Text('Seçiniz'),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Kategori *',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final k in _ref.kategoriler)
                  DropdownMenuItem(
                    value: k['no'] as int,
                    child: Text('${k['adi']}'),
                  ),
              ],
              onChanged: (v) => setState(() => _katno = v ?? _katno),
              validator: (v) => v == null ? 'Kategori seçin' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _ref.yerler.any((k) => k['no'] == _yer)
                  ? _yer
                  : null,
              isExpanded: true,
              hint: const Text('Seçiniz'),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Yer *',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              items: [
                for (final k in _ref.yerler)
                  DropdownMenuItem(
                    value: k['no'] as int,
                    child: Text('${k['adi']}'),
                  ),
              ],
              onChanged: (v) => setState(() => _yer = v ?? _yer),
              validator: (v) => v == null ? 'Yer seçin' : null,
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _zamanSec,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Tarih ve saat *',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                child: Text(
                  '${uzunGunYaz(_tarih)} · ${saatYaz(_tarih)}',
                  style: tema.textTheme.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'İçerik',
        ikon: Icons.article_outlined,
        cocuk: Column(
          children: [
            TextFormField(
              controller: _icerik,
              minLines: 6,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'İçerik *',
                hintText: 'Faaliyetin içeriğini yazın',
                alignLabelWithHint: true,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'İçerik zorunludur' : null,
            ),
            if (!_yeni && _faaliyet != null && _faaliyet!.icerik.contains('<'))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'İçeriği değiştirirseniz kalın / liste gibi biçimler sadeleşir; değiştirmezseniz korunur.',
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notlar,
              minLines: 2,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Bilgi notu',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Haber / bağlantı',
        ikon: Icons.link_rounded,
        cocuk: TextFormField(
          controller: _haberler,
          minLines: 2,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Her satıra bir bağlantı (https://…)',
            alignLabelWithHint: true,
          ),
        ),
      ),
      ProgramKutu(
        baslik: 'Fotoğraf ve ekler',
        ikon: Icons.attach_file_rounded,
        sag: (sunucu.length + _yeniDosyalar.length) > 0
            ? Text(
                '${sunucu.length + _yeniDosyalar.length}',
                style: tema.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
        cocuk: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final d in sunucu)
              DosyaSatiri(
                ad: '${d['goruntu']}',
                boyut: d['boyut'] as int?,
                kaldir: () =>
                    setState(() => _silinecekDosyalar.add('${d['ad']}')),
              ),
            for (final d in _yeniDosyalar)
              DosyaSatiri(
                ad: d.ad,
                boyut: d.boyut,
                etiket: 'gönderilecek',
                kaldir: () => setState(() {
                  _yeniDosyalar.remove(d);
                  try {
                    File(d.yol).deleteSync();
                  } catch (_) {}
                }),
              ),
            if (_silinecekDosyalar.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_silinecekDosyalar.length} dosya kaydedince silinecek.',
                  style: tema.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            const SizedBox(height: 4),
            DosyaEkleDugmeleri(
              secildi: (l) => setState(() => _yeniDosyalar.addAll(l)),
            ),
          ],
        ),
      ),
      if (_hata != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_hata!, style: TextStyle(color: cs.error)),
        ),
    ];
  }
}
