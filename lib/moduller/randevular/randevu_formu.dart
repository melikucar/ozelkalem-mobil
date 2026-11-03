import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/randevu.dart';
import '../../veri/randevu_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'randevu_ortak.dart';

/// Yeni randevu / düzenleme (web "Randevu" penceresinin karşılığı): kategori, kişi / kurum, ünvan, telefon, tarih-saat, süre,
/// yer, durum, notlar; durum "Randevu Verildi" ise hatırlatıcı; rehbere kayıt / kara liste ve SMS ile bildirim.
/// Seçilen aralıkta takvimde başka program varsa (bağlantı varken) uyarılır. Kayıt önce cihaza yazılır.
class RandevuFormu extends StatefulWidget {
  const RandevuFormu({
    super.key,
    required this.veri,
    this.yerelId,
    this.baslangic,
  });

  final VeriKatmani veri;

  /// Doluysa düzenleme, boşsa yeni randevu.
  final int? yerelId;
  final DateTime? baslangic;

  @override
  State<RandevuFormu> createState() => _RandevuFormuState();
}

class _RandevuFormuState extends State<RandevuFormu> {
  final _form = GlobalKey<FormState>();
  final _adi = TextEditingController();
  final _unvan = TextEditingController();
  final _telefon = TextEditingController();
  final _yer = TextEditingController();
  final _notlar = TextEditingController();

  late DateTime _tarih;
  int _sure = 30;
  int _katno = 0;
  int _durum = 0;
  int? _hat = 30; // null: mevcut hatırlatıcılar korunur; -1: yok
  bool _sms = false;
  bool _rehber = false;
  int _rehberKat = 0;
  bool _kara = false;

  Randevu? _randevu;
  RandevuReferans _ref = RandevuReferans({});
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;
  List<Map<String, dynamic>> _cakisma = [];
  Timer? _bekle;

  RandevuDeposu get _depo => widget.veri.randevular;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    final b = widget.baslangic ?? DateTime.now().add(const Duration(hours: 1));
    _tarih = DateTime(b.year, b.month, b.day, b.hour, 0);
    _yukle();
  }

  @override
  void dispose() {
    _bekle?.cancel();
    for (final c in [_adi, _unvan, _telefon, _yer, _notlar]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final ref = RandevuReferans(await _depo.referans());
    Randevu? r;
    if (!_yeni) r = await _depo.getir(widget.yerelId!);
    if (!mounted) return;
    setState(() {
      _ref = ref;
      _randevu = r;
      if (r != null) {
        _adi.text = r.adi;
        _unvan.text = r.unvan;
        _telefon.text = r.telefon;
        _yer.text = r.yer;
        _notlar.text = r.notlar;
        _tarih = r.bas;
        _sure = r.sureDk;
        _katno = r.katno;
        _durum = r.durum;
        _hat = null;
      } else {
        _katno = 0;
        _durum = 0;
      }
      _hazir = true;
    });
    _musaitlikBekle();
  }

  // ------------------------------------------------------------------ zaman ve çakışma

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
    _musaitlikBekle();
  }

  void _musaitlikBekle() {
    _bekle?.cancel();
    _bekle = Timer(const Duration(milliseconds: 500), _musaitlik);
  }

  Future<void> _musaitlik() async {
    final senk = widget.veri.motor.randevuSenkron;
    if (senk == null) return;
    try {
      final c = await senk.musaitlik(
        randevuZamanYaz(_tarih),
        _sure,
        _randevu?.no,
      );
      if (mounted) setState(() => _cakisma = c);
    } catch (_) {
      // çevrimdışı: uyarı verilemez, kayıt yine yapılır
      if (mounted) setState(() => _cakisma = []);
    }
  }

  // ------------------------------------------------------------------ kaydet

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
      final takvimde = _ref.takvimeAlinir(_durum);
      final tel = _telefon.text.trim();
      await _depo.kaydet(
        {
          'katno': _katno,
          'durum': _durum,
          'adi': _adi.text.trim(),
          'unvan': _unvan.text.trim(),
          'telefon': tel,
          'tarih': randevuZamanYaz(_tarih),
          'sure_dk': _sure,
          'yer': _yer.text.trim(),
          'notlar': _notlar.text.trim(),
        },
        yerelId: widget.yerelId,
        hatirlatici: takvimde ? _hat : null,
        ekstra: {
          if (_sms && tel.isNotEmpty) 'sms_randevu': 1,
          if (_rehber && tel.isNotEmpty) ...{
            'rehber_kayit': 1,
            'rehber_kategori': _rehberKat,
          },
          if (_kara && tel.isNotEmpty) 'kara_liste': 1,
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

  // ------------------------------------------------------------------ görünüm

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
            ikon: Icons.event_available_outlined,
            baslik: _yeni ? 'YENİ RANDEVU' : 'RANDEVUYU DÜZENLE',
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
                                children: _icerik(tema),
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
            label: Text(_yeni ? 'Randevuyu kaydet' : 'Değişiklikleri kaydet'),
          ),
        ),
      ),
    ),
  );

  List<Widget> _icerik(ThemeData tema) {
    final cs = tema.colorScheme;
    final takvimde = _ref.takvimeAlinir(_durum);
    final telVar = _telefon.text.trim().isNotEmpty;
    return [
      ProgramKutu(
        baslik: 'Randevu',
        ikon: Icons.event_available_outlined,
        cocuk: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_ref.kategoriler.isNotEmpty) ...[
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
                validator: (v) => v == null ? 'Kategori seçin' : null,
                onChanged: (v) => setState(() => _katno = v ?? _katno),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _adi,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'İlgili kişi / kurum *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Kişi ya da kurum adı zorunludur'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _unvan,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ünvan',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _telefon,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+() \-]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Telefon',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Zaman ve yer',
        ikon: Icons.schedule_rounded,
        cocuk: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 14),
            Text('Süre', style: tema.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s
                    in _ref.sureler.isEmpty
                        ? [
                            {'dakika': 30, 'etiket': '30 dk'},
                            {'dakika': 60, 'etiket': '1 saat'},
                          ]
                        : _ref.sureler)
                  ChoiceChip(
                    label: Text('${s['etiket']}'),
                    selected: _sure == s['dakika'],
                    onSelected: (_) {
                      setState(() => _sure = s['dakika'] as int);
                      _musaitlikBekle();
                    },
                  ),
              ],
            ),
            if (_cakisma.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber.shade900,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bu aralıkta takvimde başka program var:\n'
                        '${_cakisma.map((c) => '• ${c['saat']}  ${c['adi']}').join('\n')}',
                        style: tema.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _yer,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Yer',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Durum',
        ikon: Icons.flag_outlined,
        cocuk: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _ref.durumlar.any((d) => d['no'] == _durum)
                  ? _durum
                  : null,
              isExpanded: true,
              hint: const Text('Seçiniz'),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Durum *',
                prefixIcon: Icon(Icons.flag_outlined),
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
                          color: _ref.durumRengi(d['no'] as int),
                        ),
                        const SizedBox(width: 10),
                        Text('${d['adi']}'),
                      ],
                    ),
                  ),
              ],
              validator: (v) => v == null ? 'Durum seçin' : null,
              onChanged: (v) => setState(() => _durum = v ?? _durum),
            ),
            if (takvimde) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.event_available_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu durumda randevu program takvimine işlenir.',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _hat,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Hatırlatıcı',
                  prefixIcon: Icon(Icons.notifications_active_outlined),
                ),
                items: [
                  if (!_yeni)
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Mevcut hatırlatıcı korunsun'),
                    ),
                  const DropdownMenuItem<int?>(
                    value: -1,
                    child: Text('Hatırlatıcı yok'),
                  ),
                  for (final h in _ref.hatirlaticilar)
                    DropdownMenuItem<int?>(
                      value: h['dakika'] as int,
                      child: Text('${h['etiket']}'),
                    ),
                ],
                onChanged: (v) => setState(() => _hat = v),
              ),
            ],
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Notlar',
        ikon: Icons.notes_rounded,
        cocuk: TextFormField(
          controller: _notlar,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Randevuyla ilgili notlar',
            alignLabelWithHint: true,
          ),
        ),
      ),
      if (telVar)
        ProgramKutu(
          baslik: 'Telefon ve bildirim',
          ikon: Icons.contacts_outlined,
          cocuk: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Telefon rehberine kaydet'),
                value: _rehber,
                onChanged: (v) => setState(() => _rehber = v),
              ),
              if (_rehber && _ref.rehberKategorileri.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DropdownButtonFormField<int>(
                    initialValue: _rehberKat == 0 ? null : _rehberKat,
                    isExpanded: true,
                    hint: const Text('Seçiniz'),
                    decoration: const InputDecoration(
                      labelText: 'Rehber kategorisi *',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    validator: (v) =>
                        v == null ? 'Rehber kategorisi seçin' : null,
                    items: [
                      for (final k in _ref.rehberKategorileri)
                        DropdownMenuItem(
                          value: k['no'] as int,
                          child: Text('${k['adi']}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _rehberKat = v ?? 0),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Kara listeye al'),
                value: _kara,
                onChanged: (v) => setState(() => _kara = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Randevu SMS’i gönder'),
                subtitle: Text(
                  _ref.smsHazir
                      ? 'Kayıt sunucuya ulaşınca kişiye randevu bilgisi SMS ile gider.'
                      : 'SMS ayarları tanımlı değil; gönderilemeyebilir.',
                ),
                value: _sms,
                onChanged: (v) => setState(() => _sms = v),
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
