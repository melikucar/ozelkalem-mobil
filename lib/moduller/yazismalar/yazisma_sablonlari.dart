import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/veri_katmani.dart';
import '../../veri/yazisma.dart';
import '../programlar/program_ortak.dart';

/// Yazı şablonları (web "Yazışma ayarları"): şablon ekle / düzenle / sil. Şablonlar sunucuda tutulur; işlemler çevrimiçi yapılır.
/// Metne `{{AD_SOYAD}}` gibi alan etiketleri eklenebilir; yazı hazırlanırken seçilen talepten dolar.
class YazismaSablonlari extends StatefulWidget {
  const YazismaSablonlari({super.key, required this.veri});

  final VeriKatmani veri;

  @override
  State<YazismaSablonlari> createState() => _YazismaSablonlariState();
}

class _YazismaSablonlariState extends State<YazismaSablonlari> {
  YazismaReferans _ref = YazismaReferans({});
  bool _yuklendi = false;

  @override
  void initState() {
    super.initState();
    widget.veri.yazismalar.addListener(_yukle);
    _yukle();
  }

  @override
  void dispose() {
    widget.veri.yazismalar.removeListener(_yukle);
    super.dispose();
  }

  Future<void> _yukle() async {
    final r = YazismaReferans(await widget.veri.yazismalar.referans());
    if (mounted) {
      setState(() {
        _ref = r;
        _yuklendi = true;
      });
    }
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _duzenle([YazismaSablon? s]) async {
    final sonuc = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SablonFormu(veri: widget.veri, sablon: s, ref: _ref),
    );
    if (sonuc == true)
      _mesaj(s == null ? 'Şablon eklendi.' : 'Şablon güncellendi.');
  }

  Future<void> _sil(YazismaSablon s) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Şablon silinsin mi?'),
        content: Text('"${s.adi}" şablonu çöp kutusuna taşınır.'),
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
    try {
      await widget.veri.motor.yazismaSenkron!.sablonSil(s.no);
      _mesaj('Şablon silindi.');
    } on ApiHata catch (e) {
      _mesaj(e.agHatasi ? 'Silmek için internet bağlantısı gerekir.' : e.mesaj);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    return Scaffold(
      floatingActionButton: KompaktDugme(
        etiket: 'Yeni şablon',
        onPressed: () => _duzenle(),
      ),
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.description_outlined,
            baslik: 'YAZI ŞABLONLARI',
            altBaslik: '${_ref.sablonlar.length} şablon',
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
              child: !_yuklendi
                  ? const Center(child: CircularProgressIndicator())
                  : _ref.sablonlar.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'Henüz şablon yok. Sık kullandığınız yazılar için sağ alttaki düğmeyle şablon ekleyin.',
                          textAlign: TextAlign.center,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
                          itemCount: _ref.sablonlar.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (c, i) {
                            final s = _ref.sablonlar[i];
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
                                  onTap: () => _duzenle(s),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      6,
                                      12,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s.adi,
                                                style: tema.textTheme.titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                s.icerik.replaceAll('\n', ' '),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: tema.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Sil',
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                          onPressed: () => _sil(s),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SablonFormu extends StatefulWidget {
  const _SablonFormu({required this.veri, required this.ref, this.sablon});

  final VeriKatmani veri;
  final YazismaReferans ref;
  final YazismaSablon? sablon;

  @override
  State<_SablonFormu> createState() => _SablonFormuState();
}

class _SablonFormuState extends State<_SablonFormu> {
  final _form = GlobalKey<FormState>();
  late final _adi = TextEditingController(text: widget.sablon?.adi ?? '');
  late final _icerik = TextEditingController(text: widget.sablon?.icerik ?? '');
  bool _gidiyor = false;
  String? _hata;

  @override
  void dispose() {
    _adi.dispose();
    _icerik.dispose();
    super.dispose();
  }

  void _etiketEkle(String alan) {
    final t = _icerik.text;
    final sel = _icerik.selection;
    final bas = sel.isValid ? sel.start : t.length;
    final son = sel.isValid ? sel.end : t.length;
    final yeni = '{{$alan}}';
    _icerik.value = TextEditingValue(
      text: t.replaceRange(bas, son, yeni),
      selection: TextSelection.collapsed(offset: bas + yeni.length),
    );
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _gidiyor = true;
      _hata = null;
    });
    try {
      await widget.veri.motor.yazismaSenkron!.sablonKaydet(
        _adi.text.trim(),
        _icerik.text.trim(),
        no: widget.sablon?.no,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _gidiyor = false;
          _hata = e.agHatasi
              ? 'Kaydetmek için internet bağlantısı gerekir.'
              : e.mesaj;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.sablon == null ? 'Yeni şablon' : 'Şablonu düzenle',
                  style: tema.textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _adi,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Şablon adı *',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Şablon adı zorunludur'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _icerik,
                  minLines: 6,
                  maxLines: 14,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Şablon metni',
                    alignLabelWithHint: true,
                  ),
                ),
                if (widget.ref.alanlar.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'İmlecin olduğu yere alan ekle',
                    style: tema.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: [
                      for (final e in widget.ref.alanlar.entries)
                        ActionChip(
                          label: Text(e.value),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _etiketEkle(e.key),
                        ),
                    ],
                  ),
                ],
                if (_hata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _hata!,
                      style: TextStyle(color: tema.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _gidiyor ? null : _kaydet,
                  icon: _gidiyor
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Kaydet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
