import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/rehber.dart';
import '../../veri/rehber_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'rehber_ortak.dart';

/// Yeni kişi / kişi düzenleme (web "Rehber kaydı" penceresinin karşılığı): ad, ünvan, kategori, telefonlar (cep, iş + dahili, faks),
/// e-posta, adres, doğum günü, not ve kara liste. [baslangic]: yeni kayıtta önceden doldurulacak alanlar (görüşmeden, cihaz rehberinden).
class KisiFormu extends StatefulWidget {
  const KisiFormu({
    super.key,
    required this.veri,
    this.yerelId,
    this.baslangic,
    this.kapaninca,
  });

  final VeriKatmani veri;
  final int? yerelId;
  final Map<String, Object?>? baslangic;
  final ValueChanged<int>? kapaninca;

  @override
  State<KisiFormu> createState() => _KisiFormuState();
}

class _KisiFormuState extends State<KisiFormu> {
  final _form = GlobalKey<FormState>();
  final _adi = TextEditingController();
  final _unvan = TextEditingController();
  final _cep1 = TextEditingController();
  final _cep2 = TextEditingController();
  final _is1 = TextEditingController();
  final _isd1 = TextEditingController();
  final _is2 = TextEditingController();
  final _isd2 = TextEditingController();
  final _faks = TextEditingController();
  final _email = TextEditingController();
  final _adres = TextEditingController();
  final _notu = TextEditingController();

  int _katno = 0;
  bool _kara = false;
  DateTime? _dogum;
  RehberReferans _ref = RehberReferans({});
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;

  RehberDeposu get _depo => widget.veri.rehber;
  bool get _yeni => widget.yerelId == null;

  List<TextEditingController> get _tumu => [
    _adi,
    _unvan,
    _cep1,
    _cep2,
    _is1,
    _isd1,
    _is2,
    _isd2,
    _faks,
    _email,
    _adres,
    _notu,
  ];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final c in _tumu) {
      c.dispose();
    }
    super.dispose();
  }

  void _doldur(Map<String, Object?> m) {
    void y(TextEditingController c, String k) => c.text = '${m[k] ?? ''}';
    y(_adi, 'adi');
    y(_unvan, 'unvan');
    y(_cep1, 'cep1');
    y(_cep2, 'cep2');
    y(_is1, 'is1');
    y(_isd1, 'isd1');
    y(_is2, 'is2');
    y(_isd2, 'isd2');
    y(_faks, 'faks');
    y(_email, 'email');
    y(_adres, 'adres');
    y(_notu, 'notu');
    _katno = (m['katno'] as num?)?.toInt() ?? _katno;
    _kara = m['kara'] == 1 || m['kara'] == true;
    final d = '${m['dogum'] ?? ''}';
    _dogum = d.length >= 10 ? DateTime.tryParse(d.substring(0, 10)) : null;
  }

  Future<void> _yukle() async {
    final ref = RehberReferans(await _depo.referans());
    Kisi? k;
    if (!_yeni) k = await _depo.kisiGetir(widget.yerelId!);
    if (!mounted) return;
    setState(() {
      _ref = ref;
      if (k != null) {
        _doldur(k.v);
      } else if (widget.baslangic != null) {
        _doldur(widget.baslangic!);
      }
      if (!ref.kategoriler.any((x) => x['no'] == _katno)) _katno = 0;
      _hazir = true;
    });
  }

  Future<void> _dogumSec() async {
    final simdi = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dogum ?? DateTime(simdi.year - 30, 1, 1),
      firstDate: DateTime(1900),
      lastDate: simdi,
      helpText: 'Doğum günü',
    );
    if (d != null) setState(() => _dogum = d);
  }

  String _gunYaz(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

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
    if (_katno == 0) {
      setState(
        () => _hata = 'Kategori seçin. Kategori yoksa Rehber ▸ ⋮ ▸ Kategoriler’den ekleyin.',
      );
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final adi = _adi.text.trim();
      final cep = _cep1.text.trim();
      if (_yeni && cep.isNotEmpty) {
        final var_ = await _depo.kisiBul(adi, cep);
        if (var_ != null && var_.cep1.trim() == cep) {
          setState(() {
            _kaydediliyor = false;
            _hata = 'Bu kişi aynı cep telefonuyla rehberde zaten kayıtlı.';
          });
          return;
        }
      }
      final id = await _depo.kisiKaydet({
        'katno': _katno,
        'adi': adi,
        'unvan': _unvan.text.trim(),
        'cep1': cep,
        'cep2': _cep2.text.trim(),
        'is1': _is1.text.trim(),
        'isd1': _isd1.text.replaceAll(RegExp(r'\D'), ''),
        'is2': _is2.text.trim(),
        'isd2': _isd2.text.replaceAll(RegExp(r'\D'), ''),
        'faks': _faks.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'adres': _adres.text.trim(),
        'notu': _notu.text.trim(),
        'dogum': _dogum == null
            ? ''
            : '${_dogum!.year.toString().padLeft(4, '0')}-${_dogum!.month.toString().padLeft(2, '0')}-${_dogum!.day.toString().padLeft(2, '0')}',
        'kara': _kara,
      }, yerelId: widget.yerelId);
      widget.kapaninca?.call(id);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _kaydediliyor = false;
          _hata = 'Kaydedilemedi: $e';
        });
      }
    }
  }

  static final _telSuzgec = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+() \-.]')),
  ];

  Widget _tel(
    TextEditingController c,
    String etiket, {
    IconData ikon = Icons.phone_android_outlined,
  }) => TextFormField(
    controller: c,
    keyboardType: TextInputType.phone,
    inputFormatters: _telSuzgec,
    decoration: InputDecoration(labelText: etiket, prefixIcon: Icon(ikon)),
  );

  Widget _telDahili(
    TextEditingController c,
    TextEditingController d,
    String etiket,
  ) => Row(
    children: [
      Expanded(
        flex: 3,
        child: TextFormField(
          controller: c,
          keyboardType: TextInputType.phone,
          inputFormatters: _telSuzgec,
          decoration: InputDecoration(
            labelText: etiket,
            prefixIcon: const Icon(Icons.business_outlined),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: TextFormField(
          controller: d,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Dahili'),
        ),
      ),
    ],
  );

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
    final cs = tema.colorScheme;
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.contacts_outlined,
            baslik: _yeni ? 'YENİ KİŞİ' : 'KİŞİYİ DÜZENLE',
            altBaslik: 'Rehber kaydı',
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
                                children: [
                                  ProgramKutu(
                                    baslik: 'Kişi / kurum',
                                    ikon: Icons.person_outline_rounded,
                                    cocuk: Column(
                                      children: [
                                        TextFormField(
                                          controller: _adi,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Adı soyadı / kurum adı *',
                                            prefixIcon: Icon(
                                              Icons.badge_outlined,
                                            ),
                                          ),
                                          validator: (v) =>
                                              (v == null || v.trim().isEmpty)
                                              ? 'Ad ya da kurum adı zorunludur'
                                              : null,
                                        ),
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _unvan,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: const InputDecoration(
                                            labelText: 'Ünvan',
                                            prefixIcon: Icon(
                                              Icons.work_outline_rounded,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          initialValue:
                                              _ref.kategoriler.any(
                                                (x) => x['no'] == _katno,
                                              )
                                              ? _katno
                                              : null,
                                          isExpanded: true,
                                          hint: const Text('Seçiniz'),
                                          decoration: const InputDecoration(
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            labelText: 'Kategori *',
                                            prefixIcon: Icon(
                                              Icons.category_outlined,
                                            ),
                                          ),
                                          items: [
                                            for (final k in _ref.kategoriler)
                                              DropdownMenuItem(
                                                value: k['no'] as int,
                                                child: Text('${k['adi']}'),
                                              ),
                                          ],
                                          onChanged: (v) => setState(
                                            () => _katno = v ?? _katno,
                                          ),
                                          validator: (v) => v == null
                                              ? 'Kategori seçin'
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                  ProgramKutu(
                                    baslik: 'Telefonlar',
                                    ikon: Icons.phone_outlined,
                                    cocuk: Column(
                                      children: [
                                        _tel(_cep1, 'Cep telefonu 1'),
                                        const SizedBox(height: 14),
                                        _tel(_cep2, 'Cep telefonu 2'),
                                        const SizedBox(height: 14),
                                        _telDahili(
                                          _is1,
                                          _isd1,
                                          'İş telefonu 1',
                                        ),
                                        const SizedBox(height: 14),
                                        _telDahili(
                                          _is2,
                                          _isd2,
                                          'İş telefonu 2',
                                        ),
                                        const SizedBox(height: 14),
                                        _tel(
                                          _faks,
                                          'Faks',
                                          ikon: Icons.print_outlined,
                                        ),
                                      ],
                                    ),
                                  ),
                                  ProgramKutu(
                                    baslik: 'Diğer bilgiler',
                                    ikon: Icons.info_outline_rounded,
                                    cocuk: Column(
                                      children: [
                                        TextFormField(
                                          controller: _email,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          decoration: const InputDecoration(
                                            labelText: 'E-posta',
                                            prefixIcon: Icon(
                                              Icons.alternate_email,
                                            ),
                                          ),
                                          validator: (v) {
                                            final t = (v ?? '').trim();
                                            if (t.isEmpty) return null;
                                            return RegExp(
                                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                                ).hasMatch(t)
                                                ? null
                                                : 'E-posta adresi geçersiz';
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _adres,
                                          minLines: 2,
                                          maxLines: 4,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: const InputDecoration(
                                            labelText: 'Adres',
                                            prefixIcon: Icon(
                                              Icons.place_outlined,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          onTap: _dogumSec,
                                          child: InputDecorator(
                                            decoration: InputDecoration(
                                              labelText: 'Doğum günü',
                                              prefixIcon: const Icon(
                                                Icons.cake_outlined,
                                              ),
                                              suffixIcon: _dogum == null
                                                  ? null
                                                  : IconButton(
                                                      icon: const Icon(
                                                        Icons.close_rounded,
                                                      ),
                                                      onPressed: () => setState(
                                                        () => _dogum = null,
                                                      ),
                                                    ),
                                            ),
                                            child: Text(
                                              _dogum == null
                                                  ? 'Seçilmedi'
                                                  : _gunYaz(_dogum!),
                                              style: tema.textTheme.bodyLarge
                                                  ?.copyWith(
                                                    color: _dogum == null
                                                        ? cs.onSurfaceVariant
                                                        : null,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _notu,
                                          minLines: 2,
                                          maxLines: 6,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: const InputDecoration(
                                            labelText: 'Bilgi notu',
                                            alignLabelWithHint: true,
                                          ),
                                        ),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text('Kara liste'),
                                          subtitle: const Text(
                                            'Bu kişiyle ilgili kayıtlarda uyarı gösterilir.',
                                          ),
                                          value: _kara,
                                          onChanged: (v) =>
                                              setState(() => _kara = v),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_hata != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        _hata!,
                                        style: TextStyle(color: cs.error),
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
          if (_hazir)
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                10 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
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
                      label: Text(
                        _yeni ? 'Kişiyi kaydet' : 'Değişiklikleri kaydet',
                      ),
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
