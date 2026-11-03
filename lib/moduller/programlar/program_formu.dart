import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/program.dart';
import '../../veri/program_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/modul_hero.dart';
import 'program_ortak.dart';

/// Yeni program / program düzenleme (web "Program Ekle / Düzenle" penceresinin karşılığı): başlık, başlangıç-bitiş,
/// yer, renk, hatırlatıcılar (dakika seçenekleri + özel, uygulama / e-posta / SMS kanalları ve alıcılar), notlar ve ekler.
/// Kayıt önce cihaza yazılır, bağlantı varken sunucuya gider.
class ProgramFormu extends StatefulWidget {
  const ProgramFormu({
    super.key,
    required this.veri,
    this.yerelId,
    this.baslangic,
  });

  final VeriKatmani veri;

  /// Doluysa düzenleme, boşsa yeni program.
  final int? yerelId;

  /// Yeni programın varsayılan başlangıcı.
  final DateTime? baslangic;

  @override
  State<ProgramFormu> createState() => _ProgramFormuState();
}

class _ProgramFormuState extends State<ProgramFormu> {
  final _form = GlobalKey<FormState>();
  final _adi = TextEditingController();
  final _yer = TextEditingController();
  final _notlar = TextEditingController();
  final _ozelDeger = TextEditingController(text: '45');

  late DateTime _bas;
  late DateTime _bit;
  String _renk = varsayilanProgramRengi;
  HatirlaticiAyar _hat = const HatirlaticiAyar();
  bool _hatDegisti = false;
  String _ozelBirim = 'dk';

  Program? _program;
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;
  Map<String, dynamic> _referans = {};
  Map<String, dynamic>? _ek;
  final List<SecilenDosya> _yeniDosyalar = [];
  final Set<String> _silinecekDosyalar = {};

  ProgramDeposu get _depo => widget.veri.programlar;
  bool get _yeni => widget.yerelId == null;

  static const _hazirDakikalar = [0, 10, 30, 60, 120, 300, 1440, 2880, 10080];

  @override
  void initState() {
    super.initState();
    final b = widget.baslangic ?? DateTime.now();
    _bas = DateTime(b.year, b.month, b.day, b.hour, b.minute);
    _bit = _bas.add(const Duration(hours: 1));
    _yukle();
  }

  @override
  void dispose() {
    for (final c in [_adi, _yer, _notlar, _ozelDeger]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final ref = await _depo.referans();
    Program? p;
    Map<String, dynamic>? ek;
    if (!_yeni) {
      p = await _depo.getir(widget.yerelId!);
      if (p?.no != null) ek = await _depo.ekOku(p!.no!);
    }
    if (!mounted) return;
    setState(() {
      _referans = ref;
      _program = p;
      _ek = ek;
      if (p != null) {
        _adi.text = p.adi;
        _yer.text = p.yer;
        _notlar.text = p.notlar;
        _bas = p.bas;
        _bit = p.bit;
        _renk = p.renkHex;
        _hat = p.hatirlatici ?? const HatirlaticiAyar();
      }
      _hazir = true;
    });
  }

  // ------------------------------------------------------------------ zaman

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

  Future<void> _basSec() async {
    final z = await _zamanSec(_bas);
    if (z == null) return;
    final sure = _bit.difference(_bas);
    setState(() {
      _bas = z;
      _bit = z.add(
        sure.inMinutes < 1 ? const Duration(hours: 1) : sure,
      ); // süre korunur
    });
  }

  Future<void> _bitSec() async {
    final z = await _zamanSec(_bit);
    if (z == null) return;
    setState(() => _bit = z);
  }

  void _sure(Duration s) => setState(() => _bit = _bas.add(s));

  void _tumGun() => setState(() {
    _bas = DateTime(_bas.year, _bas.month, _bas.day);
    _bit = DateTime(_bas.year, _bas.month, _bas.day, 23, 59);
  });

  // ------------------------------------------------------------------ hatırlatıcı

  void _dakikaAcKapat(int dk) {
    final l = [..._hat.dakikalar];
    if (l.contains(dk)) {
      l.remove(dk);
    } else if (l.length < 8) {
      l.add(dk);
    } else {
      _uyar('En çok 8 hatırlatıcı eklenebilir.');
      return;
    }
    l.sort();
    setState(() {
      _hat = _hat.kopya(dakikalar: l);
      _hatDegisti = true;
    });
  }

  void _ozelEkle() {
    final n = int.tryParse(_ozelDeger.text.trim());
    if (n == null || n < 1) {
      _uyar('Geçerli bir sayı girin.');
      return;
    }
    final dk = switch (_ozelBirim) {
      'sa' => n * 60,
      'gun' => n * 1440,
      _ => n,
    };
    if (dk > 60 * 1440) {
      _uyar('En çok 60 gün öncesi seçilebilir.');
      return;
    }
    if (!_hat.dakikalar.contains(dk)) _dakikaAcKapat(dk);
  }

  void _kanal({bool? uygulama, bool? eposta, bool? sms}) {
    var h = _hat.kopya(uygulama: uygulama, eposta: eposta, sms: sms);
    if (!h.uygulama && !h.eposta && !h.sms) {
      h = h.kopya(uygulama: true); // en az bir kanal
    }
    setState(() {
      _hat = h;
      _hatDegisti = true;
    });
  }

  Future<void> _kisiSec(bool sms) async {
    final liste =
        ((_referans[sms ? 'sms_kisiler' : 'eposta_kisiler'] as List?) ??
                const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    if (liste.isEmpty) {
      _uyar('Kişi listesi cihazda yok; bağlantı gelince yüklenir.');
      return;
    }
    final secili = {...(sms ? _hat.smsKisiler : _hat.epostaKisiler)};
    final sonuc = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(c).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sms ? 'SMS alıcıları' : 'E-posta alıcıları',
                          style: Theme.of(c).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, secili),
                        child: const Text('Tamam'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final k in liste)
                        CheckboxListTile(
                          value: secili.contains((k['no'] as num).toInt()),
                          onChanged: (v) => set(() {
                            final n = (k['no'] as num).toInt();
                            v == true ? secili.add(n) : secili.remove(n);
                          }),
                          title: Text('${k['adi']}'),
                          subtitle: sms
                              ? Text('•••${k['tel_son']}')
                              : (k['adres_var'] == true
                                    ? null
                                    : const Text(
                                        'E-posta adresi tanımlı değil',
                                      )),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (sonuc == null) return;
    setState(() {
      _hat = sms
          ? _hat.kopya(smsKisiler: sonuc.toList())
          : _hat.kopya(epostaKisiler: sonuc.toList());
      _hatDegisti = true;
    });
  }

  void _uyar(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  // ------------------------------------------------------------------ kaydet

  Future<void> _kaydet() async {
    if (_kaydediliyor || !_form.currentState!.validate()) return;
    if (!_bit.isAfter(_bas)) {
      setState(() => _hata = 'Bitiş, başlangıçtan sonra olmalı.');
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final id = await _depo.kaydet(
        {
          'adi': _adi.text.trim(),
          'tarih1': programZamanYaz(_bas),
          'tarih2': programZamanYaz(_bit),
          'yer': _yer.text.trim(),
          'notlar': _notlar.text.trim(),
          'renk': _renk,
        },
        yerelId: widget.yerelId,
        // Yeni programda ve değiştirilmişse hatırlatıcılar gönderilir; aksi halde mevcutlar korunur
        hatirlatici: (_yeni || _hatDegisti) ? _hat : null,
      );
      for (final d in _yeniDosyalar) {
        await _depo.dosyaEkle(id, yol: d.yol, ad: d.ad, boyut: d.boyut);
      }
      final no = _program?.no;
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
            ikon: Icons.event_outlined,
            baslik: _yeni ? 'YENİ PROGRAM' : 'PROGRAMI DÜZENLE',
            altBaslik: uzunGunYaz(_bas),
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
            label: Text(_yeni ? 'Programı kaydet' : 'Değişiklikleri kaydet'),
          ),
        ),
      ),
    ),
  );

  List<Widget> _icerik(ThemeData tema) {
    final cs = tema.colorScheme;
    final sure = _bit.difference(_bas);
    return [
      ProgramKutu(
        baslik: 'Program',
        ikon: Icons.edit_calendar_outlined,
        cocuk: Column(
          children: [
            TextFormField(
              controller: _adi,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Başlık *',
                hintText: 'Programın adını yazın',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Başlık zorunludur' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _yer,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Yer',
                hintText: 'Programın yapılacağı yer',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Renk', style: tema.textTheme.labelMedium),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                const bosluk = 6.0;
                final boy =
                    ((c.maxWidth - bosluk * (programRenkleri.length - 1)) /
                            programRenkleri.length)
                        .clamp(18.0, 28.0);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final r in programRenkleri)
                      GestureDetector(
                        onTap: () => setState(() => _renk = r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: boy,
                          height: boy,
                          decoration: BoxDecoration(
                            color: programRengi(r),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _renk == r
                                  ? cs.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: _renk == r
                              ? Icon(
                                  Icons.check_rounded,
                                  size: boy * 0.55,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Zaman',
        ikon: Icons.schedule_rounded,
        sag: Text(
          sureYaz(sure),
          style: tema.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        cocuk: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ZamanKutusu(
                    etiket: 'Başlangıç',
                    zaman: _bas,
                    tikla: _basSec,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ZamanKutusu(
                    etiket: 'Bitiş',
                    zaman: _bit,
                    tikla: _bitSec,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in const [
                    ('30 dk', Duration(minutes: 30)),
                    ('1 sa', Duration(hours: 1)),
                    ('2 sa', Duration(hours: 2)),
                    ('3 sa', Duration(hours: 3)),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.$1),
                        selected: sure == s.$2,
                        onSelected: (_) => _sure(s.$2),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: const Text('Tüm gün'),
                    onPressed: _tumGun,
                  ),
                ],
              ),
            ),
            if (!_bit.isAfter(_bas))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Bitiş, başlangıçtan sonra olmalı.',
                  style: TextStyle(color: cs.error, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
      _hatirlaticiKutusu(tema),
      ProgramKutu(
        baslik: 'Notlar',
        ikon: Icons.notes_rounded,
        cocuk: TextFormField(
          controller: _notlar,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Program notları'),
        ),
      ),
      _eklerKutusu(tema),
      if (_hata != null)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.error.withValues(alpha: 0.35)),
          ),
          child: Text(_hata!, style: TextStyle(color: cs.error)),
        ),
    ];
  }

  Widget _hatirlaticiKutusu(ThemeData tema) {
    final cs = tema.colorScheme;
    final ozel = _hat.dakikalar
        .where((d) => !_hazirDakikalar.contains(d))
        .toList();
    final kisiSms = ((_referans['sms_kisiler'] as List?) ?? const []).length;
    final kisiEposta =
        ((_referans['eposta_kisiler'] as List?) ?? const []).length;
    Widget alici(bool sms) {
      final secim = sms ? _hat.smsAlici : _hat.epostaAlici;
      final kisiler = sms ? _hat.smsKisiler : _hat.epostaKisiler;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sms ? 'SMS kimlere gitsin?' : 'E-posta kimlere gitsin?',
              style: tema.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in [
                  ('ben', 'Yalnızca ben'),
                  ('secilen', 'Seçtiğim kişiler'),
                  ('herkes', 'Herkes (${sms ? kisiSms : kisiEposta})'),
                ])
                  ChoiceChip(
                    label: Text(s.$2),
                    selected: secim == s.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() {
                      _hat = sms
                          ? _hat.kopya(smsAlici: s.$1)
                          : _hat.kopya(epostaAlici: s.$1);
                      _hatDegisti = true;
                    }),
                  ),
              ],
            ),
            if (secim == 'secilen')
              TextButton.icon(
                onPressed: () => _kisiSec(sms),
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(
                  kisiler.isEmpty
                      ? 'Kişi seç'
                      : '${kisiler.length} kişi seçili · değiştir',
                ),
              ),
          ],
        ),
      );
    }

    return ProgramKutu(
      baslik: 'Hatırlatıcılar',
      ikon: Icons.notifications_active_outlined,
      sag: Text(
        _hat.bos ? 'Yok' : '${_hat.dakikalar.length} seçili',
        style: tema.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      cocuk: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final dk in _hazirDakikalar)
                FilterChip(
                  label: Text(hatirlaticiEtiketi(dk)),
                  selected: _hat.dakikalar.contains(dk),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _dakikaAcKapat(dk),
                ),
              for (final dk in ozel)
                InputChip(
                  label: Text(hatirlaticiEtiketi(dk)),
                  selected: true,
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => _dakikaAcKapat(dk),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _ozelDeger,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Özel',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 'dk', label: Text('dk')),
                  ButtonSegment(value: 'sa', label: Text('saat')),
                  ButtonSegment(value: 'gun', label: Text('gün')),
                ],
                selected: {_ozelBirim},
                onSelectionChanged: (s) => setState(() => _ozelBirim = s.first),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _ozelEkle,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (!_hat.bos) ...[
            const Divider(height: 26),
            Text(
              'Nasıl hatırlatılsın?',
              style: tema.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.phone_android_rounded, size: 16),
                  label: const Text('Uygulama'),
                  selected: _hat.uygulama,
                  onSelected: (v) => _kanal(uygulama: v),
                ),
                FilterChip(
                  avatar: const Icon(Icons.mail_outline_rounded, size: 16),
                  label: const Text('E-posta'),
                  selected: _hat.eposta,
                  onSelected: (v) => _kanal(eposta: v),
                ),
                FilterChip(
                  avatar: const Icon(Icons.sms_outlined, size: 16),
                  label: const Text('SMS'),
                  selected: _hat.sms,
                  onSelected: (v) => _kanal(sms: v),
                ),
              ],
            ),
            if (_hat.sms) alici(true),
            if (_hat.eposta) alici(false),
          ],
        ],
      ),
    );
  }

  Widget _eklerKutusu(ThemeData tema) {
    final sunucu = [
      for (final x in (_ek?['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ].where((d) => !_silinecekDosyalar.contains(d['ad'])).toList();
    return ProgramKutu(
      baslik: 'Ekler',
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
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 4),
          DosyaEkleDugmeleri(
            secildi: (l) => setState(() => _yeniDosyalar.addAll(l)),
          ),
        ],
      ),
    );
  }
}

class _ZamanKutusu extends StatelessWidget {
  const _ZamanKutusu({
    required this.etiket,
    required this.zaman,
    required this.tikla,
  });

  final String etiket;
  final DateTime zaman;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tikla,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiket,
                style: tema.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                saatYaz(zaman),
                style: tema.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                  height: 1.1,
                ),
              ),
              Text(
                '${zaman.day} ${trAylarKisa[zaman.month]} ${trGunlerKisa[zaman.weekday]}',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
