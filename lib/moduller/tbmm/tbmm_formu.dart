import 'dart:io';

import 'package:flutter/material.dart';

import '../../diger/dosya_islemleri.dart';
import '../../diger/modul_hero.dart';
import '../../veri/tbmm.dart';
import '../../veri/tbmm_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../programlar/program_ortak.dart';
import 'tbmm_ortak.dart';

/// Yeni kayıt / düzenleme (web "önerge ekle / düzenle" formunun karşılığı): tür, ad, tarih, içerik, bilgi notu ve ek dosyalar
/// (kameradan fotoğraf dahil). Kayıt önce cihaza yazılır.
class TbmmFormu extends StatefulWidget {
  const TbmmFormu({
    super.key,
    required this.veri,
    this.yerelId,
    this.baslangicTuru = 0,
  });

  final VeriKatmani veri;

  /// Doluysa düzenleme, boşsa yeni kayıt.
  final int? yerelId;

  /// Yeni kayıtta önceden seçili tür (0: seçilmemiş).
  final int baslangicTuru;

  @override
  State<TbmmFormu> createState() => _TbmmFormuState();
}

class _TbmmFormuState extends State<TbmmFormu> {
  final _form = GlobalKey<FormState>();
  final _adi = TextEditingController();
  final _icerik = TextEditingController();
  final _notlar = TextEditingController();

  late DateTime _tarih;
  int _tablo = 0;

  Tbmm? _kayit;
  TbmmReferans _ref = TbmmReferans({});
  Map<String, dynamic>? _ek;
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;
  String _ilkIcerik = '';
  final List<SecilenDosya> _yeniDosyalar = [];
  final Set<String> _silinecekDosyalar = {};

  TbmmDeposu get _depo => widget.veri.tbmm;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _tarih = DateTime(n.year, n.month, n.day);
    _tablo = widget.baslangicTuru;
    _yukle();
  }

  @override
  void dispose() {
    for (final c in [_adi, _icerik, _notlar]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final ref = TbmmReferans(await _depo.referans());
    Tbmm? t;
    Map<String, dynamic>? ek;
    if (!_yeni) {
      t = await _depo.getir(widget.yerelId!);
      if (t?.no != null) ek = await _depo.ekOku(t!.no!);
    }
    if (!mounted) return;
    setState(() {
      _ref = ref;
      _kayit = t;
      _ek = ek;
      if (t != null) {
        _adi.text = t.adi;
        _ilkIcerik = t.icerikDuz.trim();
        _icerik.text = _ilkIcerik;
        _notlar.text = t.notlar;
        _tarih = t.tarih;
        _tablo = t.tablo;
      }
      _hazir = true;
    });
  }

  Future<void> _tarihSec() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _tarih = d);
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
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final icerik = _icerik.text.trim();
      final id = await _depo.kaydet({
        'tablo': _tablo,
        'adi': _adi.text.trim(),
        'tarih': tbmmTarihYaz(_tarih),
        'notlar': _notlar.text.trim(),
        // biçimli (kalın, liste…) mevcut içerik yalnızca metin değiştiyse yeniden yazılır
        if (_yeni ? icerik.isNotEmpty : icerik != _ilkIcerik) 'icerik': icerik,
      }, yerelId: widget.yerelId);
      for (final d in _yeniDosyalar) {
        await _depo.dosyaEkle(id, yol: d.yol, ad: d.ad, boyut: d.boyut);
      }
      final no = _kayit?.no;
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
            ikon: tbmmIkonu(_tablo),
            baslik: _yeni ? 'YENİ KAYIT' : 'KAYDI DÜZENLE',
            altBaslik: _ref.tabloAdi(_tablo).isEmpty
                ? tbmmTarihKisa(_tarih)
                : '${_ref.tabloAdi(_tablo)} · ${tbmmTarihKisa(_tarih)}',
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
                                children: _kutular(tema),
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
            label: Text(_yeni ? 'Kaydı kaydet' : 'Değişiklikleri kaydet'),
          ),
        ),
      ),
    ),
  );

  List<Widget> _kutular(ThemeData tema) {
    final cs = tema.colorScheme;
    final tur = _ref.tabloAdi(_tablo);
    final sunucu = [
      for (final x in (_ek?['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ].where((d) => !_silinecekDosyalar.contains(d['ad'])).toList();
    return [
      ProgramKutu(
        baslik: tur.isEmpty ? 'Kayıt' : tur,
        ikon: tbmmIkonu(_tablo),
        cocuk: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: _ref.tablolar.any((k) => k['no'] == _tablo)
                  ? _tablo
                  : null,
              isExpanded: true,
              hint: const Text('Seçiniz'),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Tür *',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                for (final k in _ref.tablolar)
                  DropdownMenuItem(
                    value: (k['no'] as num).toInt(),
                    child: Text('${k['adi']}'),
                  ),
              ],
              onChanged: (v) => setState(() => _tablo = v ?? _tablo),
              validator: (v) => v == null ? 'Tür seçin' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _adi,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: '${tur.isEmpty ? 'Kayıt' : tur} adı *',
                hintText: 'Başlığını yazınız',
                prefixIcon: const Icon(Icons.title_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ad zorunludur' : null,
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _tarihSec,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Tarih *',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                child: Text(
                  uzunGunYaz(_tarih),
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
                labelText: 'İçerik',
                hintText: 'İçerik giriniz',
                alignLabelWithHint: true,
              ),
            ),
            if (!_yeni && _kayit != null && _kayit!.icerik.contains('<'))
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
                hintText: 'Varsa bilgi notu',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Ek dosyalar',
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
