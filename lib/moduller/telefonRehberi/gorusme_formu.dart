import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/yazi_formatlari.dart';
import '../../veri/rehber.dart';
import '../../veri/rehber_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'rehber_ortak.dart';

/// Yeni telefon görüşmesi / düzenleme (web "Telefon görüşmesi" penceresinin karşılığı): kişi (rehberden öneriyle), ünvan, telefonlar,
/// konu, 1. görüşme durumu ve zamanı, isteğe bağlı takip görüşmesi, not; rehbere kaydet / kara liste.
class GorusmeFormu extends StatefulWidget {
  const GorusmeFormu({super.key, required this.veri, this.yerelId, this.kisi});

  final VeriKatmani veri;
  final int? yerelId;

  /// Yeni görüşmede önceden seçili kişi (kişi ayrıntısından "Görüşme ekle").
  final Kisi? kisi;

  @override
  State<GorusmeFormu> createState() => _GorusmeFormuState();
}

class _GorusmeFormuState extends State<GorusmeFormu> {
  final _form = GlobalKey<FormState>();
  final _adi = TextEditingController();
  final _unvan = TextEditingController();
  final _tel1 = TextEditingController();
  final _dah1 = TextEditingController();
  final _tel2 = TextEditingController();
  final _dah2 = TextEditingController();
  final _konu = TextEditingController();
  final _notum = TextEditingController();

  int _d1 = 0;
  int _d2 = 0;
  late DateTime _t1;
  late DateTime _t2;
  bool _rehberKayit = false;
  int _rehberKat = 0;
  bool _kara = false;
  bool _rehberde = false;

  RehberReferans _ref = RehberReferans({});
  List<Kisi> _oneriler = [];
  Timer? _bekle;
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;

  RehberDeposu get _depo => widget.veri.rehber;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _t1 = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    _t2 = _t1.add(const Duration(hours: 1));
    _yukle();
  }

  @override
  void dispose() {
    _bekle?.cancel();
    for (final c in [_adi, _unvan, _tel1, _dah1, _tel2, _dah2, _konu, _notum]) {
      c.dispose();
    }
    super.dispose();
  }

  void _kisiyiDoldur(Kisi k) {
    _adi.text = k.adi;
    _unvan.text = k.unvan;
    _tel1.text = k.cep1.isNotEmpty ? k.cep1 : k.is1;
    _dah1.text = k.cep1.isNotEmpty ? '' : k.isd1;
    _tel2.text = k.cep2.isNotEmpty
        ? k.cep2
        : (k.cep1.isNotEmpty ? k.is1 : k.is2);
    _dah2.text = k.cep2.isNotEmpty ? '' : (k.cep1.isNotEmpty ? k.isd1 : k.isd2);
    _rehberde = true;
    _kara = k.kara;
  }

  Future<void> _yukle() async {
    final ref = RehberReferans(await _depo.referans());
    Gorusme? g;
    if (!_yeni) g = await _depo.gorusmeGetir(widget.yerelId!);
    Kisi? rk;
    if (g != null) rk = await _depo.kisiBul(g.adi, g.tel1);
    if (!mounted) return;
    setState(() {
      _ref = ref;
      if (g != null) {
        _adi.text = g.adi;
        _unvan.text = g.unvan;
        _tel1.text = g.tel1;
        _dah1.text = g.dah1;
        _tel2.text = g.tel2;
        _dah2.text = g.dah2;
        _konu.text = g.konu;
        _notum.text = g.notum;
        _d1 = g.d1;
        _d2 = g.d2;
        _t1 = g.t1;
        _t2 = g.t2 ?? g.t1.add(const Duration(hours: 1));
        _rehberde = rk != null;
        _kara = rk?.kara ?? false;
      } else if (widget.kisi != null) {
        _kisiyiDoldur(widget.kisi!);
      }
      _hazir = true;
    });
  }

  void _adDegisti(String v) {
    _bekle?.cancel();
    _bekle = Timer(const Duration(milliseconds: 220), () async {
      final r = await _depo.kisiAra(v);
      if (mounted) setState(() => _oneriler = r);
    });
  }

  Future<DateTime?> _zamanSec(DateTime ilk) async {
    final d = await showDatePicker(
      context: context,
      initialDate: ilk,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: ilk.hour, minute: ilk.minute),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: w!,
      ),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  String _z(DateTime t) =>
      '${t.day} ${trAylar[t.month]} ${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _zamanYaz(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

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
    if (_d1 <= 0) {
      setState(() => _hata = '1. görüşme durumunu seçin.');
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final tel = _tel1.text.trim();
      await _depo.gorusmeKaydet(
        {
          'adi': _adi.text.trim(),
          'unvan': _unvan.text.trim(),
          'tel1': tel,
          'dah1': _dah1.text.replaceAll(RegExp(r'\D'), ''),
          'tel2': _tel2.text.trim(),
          'dah2': _dah2.text.replaceAll(RegExp(r'\D'), ''),
          'konu': _konu.text.trim(),
          'd1': _d1,
          'd2': _d2,
          't1': _zamanYaz(_t1),
          't2': _d2 > 0 ? _zamanYaz(_t2) : '',
          'notum': _notum.text.trim(),
        },
        yerelId: widget.yerelId,
        ekstra: {
          if (!_rehberde && _rehberKayit) ...{
            'rehber_kayit': 1,
            'rehber_kategori': _rehberKat,
          },
          // kara liste yalnızca değiştirildiyse ya da yeni kişi için işaretlendiyse gönderilir
          if (_kara || _rehberde) 'kara_liste': _kara ? 1 : 0,
        },
      );
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

  static final _telSuzgec = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+() \-.]')),
  ];

  Widget _telAlan(
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
            prefixIcon: const Icon(Icons.phone_outlined),
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
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.phone_in_talk_outlined,
            baslik: _yeni ? 'YENİ GÖRÜŞME' : 'GÖRÜŞMEYİ DÜZENLE',
            altBaslik: 'Telefon görüşmesi',
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
                                          onChanged: _adDegisti,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Adı soyadı / kurum adı *',
                                            hintText: 'Rehberden bulmak için yazmaya başlayın',
                                            prefixIcon: Icon(
                                              Icons.badge_outlined,
                                            ),
                                          ),
                                          validator: (v) =>
                                              (v == null || v.trim().isEmpty)
                                              ? 'Kişi ya da kurum adı zorunludur'
                                              : null,
                                        ),
                                        if (_oneriler.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cs.primary.withValues(
                                                alpha: 0.06,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Column(
                                              children: [
                                                for (final k in _oneriler)
                                                  ListTile(
                                                    dense: true,
                                                    leading: const Icon(
                                                      Icons.contacts_outlined,
                                                      size: 20,
                                                    ),
                                                    title: Text(trBuyuk(k.adi)),
                                                    subtitle: Text(
                                                      [
                                                        if (k.unvan
                                                            .trim()
                                                            .isNotEmpty)
                                                          k.unvan.trim(),
                                                        if (k
                                                            .anaTelefon
                                                            .isNotEmpty)
                                                          k.anaTelefon,
                                                      ].join(' · '),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    onTap: () => setState(() {
                                                      _kisiyiDoldur(k);
                                                      _oneriler = [];
                                                    }),
                                                  ),
                                              ],
                                            ),
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
                                        _telAlan(_tel1, _dah1, 'Telefon 1'),
                                        const SizedBox(height: 14),
                                        _telAlan(_tel2, _dah2, 'Telefon 2'),
                                      ],
                                    ),
                                  ),
                                  ProgramKutu(
                                    baslik: 'Görüşme',
                                    ikon: Icons.phone_in_talk_outlined,
                                    cocuk: Column(
                                      children: [
                                        TextFormField(
                                          controller: _konu,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: const InputDecoration(
                                            labelText: 'Konu',
                                            prefixIcon: Icon(
                                              Icons.subject_rounded,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          initialValue:
                                              _ref.durumlar.any(
                                                (x) => x['no'] == _d1,
                                              )
                                              ? _d1
                                              : null,
                                          isExpanded: true,
                                          hint: const Text('Seçiniz'),
                                          decoration: const InputDecoration(
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            labelText: '1. görüşme durumu *',
                                            prefixIcon: Icon(
                                              Icons.flag_outlined,
                                            ),
                                          ),
                                          items: [
                                            for (final d in _ref.durumlar)
                                              DropdownMenuItem(
                                                value: d['no'] as int,
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.circle,
                                                      size: 10,
                                                      color: gorusmeDurumRengi(
                                                        d['no'] as int,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Flexible(
                                                      child: Text(
                                                        '${d['adi']}',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) =>
                                              setState(() => _d1 = v ?? _d1),
                                          validator: (v) =>
                                              v == null ? 'Durum seçin' : null,
                                        ),
                                        const SizedBox(height: 14),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          onTap: () async {
                                            final z = await _zamanSec(_t1);
                                            if (z != null) {
                                              setState(() => _t1 = z);
                                            }
                                          },
                                          child: InputDecorator(
                                            decoration: const InputDecoration(
                                              labelText: 'Görüşme zamanı',
                                              prefixIcon: Icon(
                                                Icons.schedule_rounded,
                                              ),
                                            ),
                                            child: Text(
                                              _z(_t1),
                                              style: tema.textTheme.bodyLarge,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          initialValue:
                                              _d2 == 0 ||
                                                  _ref.durumlar.any(
                                                    (x) => x['no'] == _d2,
                                                  )
                                              ? _d2
                                              : 0,
                                          isExpanded: true,
                                          hint: const Text('Seçiniz'),
                                          decoration: const InputDecoration(
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            labelText: '2. görüşme (takip)',
                                            prefixIcon: Icon(
                                              Icons.replay_rounded,
                                            ),
                                          ),
                                          items: [
                                            const DropdownMenuItem(
                                              value: 0,
                                              child: Text(
                                                'Takip görüşmesi yok',
                                              ),
                                            ),
                                            for (final d in _ref.durumlar)
                                              DropdownMenuItem(
                                                value: d['no'] as int,
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.circle,
                                                      size: 10,
                                                      color: gorusmeDurumRengi(
                                                        d['no'] as int,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Flexible(
                                                      child: Text(
                                                        '${d['adi']}',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) =>
                                              setState(() => _d2 = v ?? 0),
                                        ),
                                        if (_d2 > 0) ...[
                                          const SizedBox(height: 14),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            onTap: () async {
                                              final z = await _zamanSec(_t2);
                                              if (z != null) {
                                                setState(() => _t2 = z);
                                              }
                                            },
                                            child: InputDecorator(
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Takip görüşmesi zamanı',
                                                prefixIcon: Icon(
                                                  Icons.event_repeat_rounded,
                                                ),
                                              ),
                                              child: Text(
                                                _z(_t2),
                                                style: tema.textTheme.bodyLarge,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _notum,
                                          minLines: 3,
                                          maxLines: 8,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: const InputDecoration(
                                            labelText: 'Notum',
                                            alignLabelWithHint: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ProgramKutu(
                                    baslik: 'Rehber',
                                    ikon: Icons.contacts_outlined,
                                    cocuk: Column(
                                      children: [
                                        if (_rehberde)
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                color: cs.primary,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Bu kişi rehberde kayıtlı.',
                                                  style:
                                                      tema.textTheme.bodyMedium,
                                                ),
                                              ),
                                            ],
                                          )
                                        else ...[
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Rehbere kaydet'),
                                            value: _rehberKayit,
                                            onChanged: (v) => setState(
                                              () => _rehberKayit = v,
                                            ),
                                          ),
                                          if (_rehberKayit &&
                                              _ref.kategoriler.isNotEmpty)
                                            DropdownButtonFormField<int>(
                                              initialValue:
                                                  _ref.kategoriler.any(
                                                    (x) =>
                                                        x['no'] == _rehberKat,
                                                  )
                                                  ? _rehberKat
                                                  : null,
                                              isExpanded: true,
                                              hint: const Text('Seçiniz'),
                                              decoration: const InputDecoration(
                                                floatingLabelBehavior:
                                                    FloatingLabelBehavior
                                                        .always,
                                                labelText: 'Rehber kategorisi',
                                              ),
                                              items: [
                                                for (final k
                                                    in _ref.kategoriler)
                                                  DropdownMenuItem(
                                                    value: k['no'] as int,
                                                    child: Text('${k['adi']}'),
                                                  ),
                                              ],
                                              validator: (v) =>
                                                  _rehberKayit && v == null
                                                  ? 'Rehber kategorisi seçin'
                                                  : null,
                                              onChanged: (v) => setState(
                                                () => _rehberKat =
                                                    v ?? _rehberKat,
                                              ),
                                            ),
                                        ],
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text('Kara listeye al'),
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
                        _yeni ? 'Görüşmeyi kaydet' : 'Değişiklikleri kaydet',
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
