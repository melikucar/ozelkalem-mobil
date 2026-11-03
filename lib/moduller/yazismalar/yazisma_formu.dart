import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../api/oturum.dart';
import '../../diger/modul_hero.dart';
import '../../veri/talep.dart';
import '../../veri/veri_katmani.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/yazisma.dart';
import '../../veri/yazisma_deposu.dart';
import '../../veri/yazisma_sablon.dart';
import '../../veri/program.dart' show programZamani;
import '../programlar/program_ortak.dart';
import 'yazisma_ortak.dart';

/// Yeni yazı / düzenleme (web "Yazı Ekle / Düzenle" sayfasının karşılığı): ilgili kişi (talep ya da kayıtsız kişi), "Sayın" muhatabı
/// (kurum önerili), şablon seçimi (alanlar talepten dolar, hitap makama göre düzelir), metin, görünüm seçenekleri ve canlı A4 önizleme.
/// Kayıt önce cihaza yazılır.
class YazismaFormu extends StatefulWidget {
  const YazismaFormu({
    super.key,
    required this.veri,
    required this.oturum,
    this.yerelId,
  });

  final VeriKatmani veri;
  final Oturum oturum;

  /// Doluysa düzenleme, boşsa yeni yazı.
  final int? yerelId;

  @override
  State<YazismaFormu> createState() => _YazismaFormuState();
}

class _YazismaFormuState extends State<YazismaFormu> {
  final _form = GlobalKey<FormState>();
  final _kisi = TextEditingController();
  final _unvan = TextEditingController();
  final _metin = TextEditingController();
  final _serbestAd = TextEditingController();

  // ilgili kişi
  int? _talepNo; // seçili talep (null: kayıtsız kişi)
  String _talepAdi = '';
  Map<String, String> _alanlar = {};
  bool _alanlarCevrimdisi = false;

  // şablon
  int _sablonNo = 0;
  String? _sablonHam;
  bool _metinElle = false;
  bool _metinYaziliyor = false;
  int _bos = 0;

  bool _logo = true;
  bool _imza = true;
  bool _imzaUnvan = true;
  bool _imzaUnvan2 = true;
  bool _altYazi = true;

  Yazisma? _yazisma;
  YazismaReferans _ref = YazismaReferans({});
  bool _hazir = false;
  bool _kaydediliyor = false;
  String _ilkMetin = '';

  YazismaDeposu get _depo => widget.veri.yazismalar;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    for (final c in [_kisi, _unvan, _metin, _serbestAd]) {
      c.addListener(_degisti);
    }
    _yukle();
  }

  @override
  void dispose() {
    for (final c in [_kisi, _unvan, _metin, _serbestAd]) {
      c.dispose();
    }
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  Future<void> _yukle() async {
    final ref = YazismaReferans(await _depo.referans());
    Yazisma? y;
    if (!_yeni) y = await _depo.getir(widget.yerelId!);
    if (!mounted) return;
    setState(() {
      _ref = ref;
      _yazisma = y;
      if (y != null) {
        _kisi.text = y.kisi;
        _unvan.text = y.unvan;
        _ilkMetin = y.icerikDuz.trim();
        _metin.text = _ilkMetin;
        _metinElle = true;
        if (y.talepBagli) {
          _talepNo = int.tryParse(y.talepEden);
          _talepAdi = y.talepAdi;
        } else {
          _serbestAd.text = y.talepEden;
        }
        _logo = y.logo;
        _imza = y.imza;
        _imzaUnvan = y.imzaUnvan;
        _imzaUnvan2 = y.imzaUnvan2;
        _altYazi = y.altYazi;
      }
      _hazir = true;
    });
  }

  // ------------------------------------------------------------------ şablon

  Map<String, String> get _veri {
    final m = <String, String>{
      for (final k in _ref.alanlar.keys) k: '',
      'BUGUN': yazismaGun(DateTime.now()),
      ..._alanlar,
    };
    final mak = widget.oturum.ben?['makam'] as Map?;
    if ((m['MAKAM_ADI'] ?? '').isEmpty && mak != null) {
      m['MAKAM_ADI'] = trBuyuk('${mak['adi'] ?? ''}');
    }
    return m;
  }

  String? get _hedef => _kisi.text.trim().isEmpty && _unvan.text.trim().isEmpty
      ? null
      : YazismaSablonMotoru.hitapTuru(_kisi.text, _unvan.text);

  void _sablonUygula() {
    final ham = _sablonHam;
    if (ham == null) return;
    final s = YazismaSablonMotoru.uygula(ham, _veri, hedef: _hedef);
    _metinYaziliyor = true;
    _metin.text = s.metin;
    _metinYaziliyor = false;
    _metinElle = false;
    setState(() => _bos = s.bos);
  }

  void _sablonSec(int no) {
    final s = _ref.sablonlar.where((x) => x.no == no).firstOrNull;
    setState(() {
      _sablonNo = no;
      _sablonHam = s?.icerik;
    });
    if (s != null) _sablonUygula();
  }

  Future<void> _talepAlanlari(int no, Talep? t) async {
    Map<String, String> a = {};
    var cevrimdisi = false;
    try {
      final v = await widget.veri.motor.api.get(
        'yazismalar/talep-bilgi?no=$no',
      );
      a = {
        for (final e in ((v['alanlar'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value ?? ''}',
      };
    } on ApiHata {
      cevrimdisi = true;
      if (t != null) {
        a = {
          'AD_SOYAD': trBuyuk(t.talepEden.trim()),
          'TCKN': t.s('tcno'),
          'TELEFON': t.s('telefon'),
        };
      }
    }
    if (!mounted) return;
    setState(() {
      _alanlar = a;
      _alanlarCevrimdisi = cevrimdisi;
    });
    if (_sablonHam != null && !_metinElle) _sablonUygula();
  }

  // ------------------------------------------------------------------ seçiciler

  Future<void> _talepSec() async {
    final t = await showModalBottomSheet<Talep>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TalepSecici(depo: widget.veri.talepler),
    );
    if (t == null || !mounted) return;
    if (t.no == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Bu talep henüz sunucuya gönderilmedi; senkron bittikten sonra seçebilirsiniz.',
            ),
          ),
        );
      return;
    }
    setState(() {
      _talepNo = t.no;
      _talepAdi = t.talepEden.trim();
      _serbestAd.clear();
    });
    await _talepAlanlari(t.no!, t);
  }

  void _kayitsiz() => setState(() {
    _talepNo = null;
    _talepAdi = '';
    _alanlar = {};
    _alanlarCevrimdisi = false;
    if (_sablonHam != null && !_metinElle) _sablonUygula();
  });

  Future<void> _kurumSec() async {
    final k = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _KurumSecici(api: widget.veri.motor.api),
    );
    if (k == null || !mounted) return;
    setState(() {
      _kisi.text = '${k['ad']}';
      _unvan.text = '${k['unvan']}';
    });
    if (_sablonHam != null && !_metinElle) {
      _sablonUygula();
    } else if (_metin.text.isNotEmpty) {
      final yeni = YazismaSablonMotoru.hitapDonustur(
        _metin.text,
        YazismaSablonMotoru.hitapTuru(_kisi.text, _unvan.text),
      );
      if (yeni != _metin.text) {
        _metinYaziliyor = true;
        _metin.text = yeni;
        _metinYaziliyor = false;
      }
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
    final kalan = YazismaSablonMotoru.kalanBosluk(_metin.text);
    if (kalan > 0) {
      final tamam = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Doldurulmamış boşluk var'),
          content: Text(
            'Metinde $kalan boşluk ya da {{alan}} işareti kaldı. Yine de kaydedilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Metne dön'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yine de kaydet'),
            ),
          ],
        ),
      );
      if (tamam != true) return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final metin = _metin.text.trim();
      final talepEden = _talepNo != null ? '$_talepNo' : _serbestAd.text.trim();
      await _depo.kaydet(
        {
          'talep_eden': talepEden,
          'talep_adi': _talepNo != null ? _talepAdi : talepEden,
          'kisi': _kisi.text.trim(),
          'unvan': _unvan.text.trim(),
          'logo': _logo,
          'imza': _imza,
          'imza_unvan': _imzaUnvan,
          'imza_unvan_2': _imzaUnvan2,
          'alt_yazi': _altYazi,
        },
        yerelId: widget.yerelId,
        // biçimli (kalın, liste…) mevcut metin yalnızca değiştirildiyse yeniden yazılır
        metin: (_yeni || metin != _ilkMetin) ? metin : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _kaydediliyor = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    }
  }

  // ------------------------------------------------------------------ arayüz

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
            ikon: Icons.mail_outline_rounded,
            baslik: _yeni ? 'YENİ YAZI' : 'YAZIYI DÜZENLE',
            altBaslik: yazismaTarihYaz(_yazisma?.tarih ?? DateTime.now()),
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
            label: Text(_yeni ? 'Yazıyı kaydet' : 'Değişiklikleri kaydet'),
          ),
        ),
      ),
    ),
  );

  List<Widget> _kutular(ThemeData tema) {
    final cs = tema.colorScheme;
    final bagli = _talepNo != null;
    final kalan = YazismaSablonMotoru.kalanBosluk(_metin.text);
    return [
      ProgramKutu(
        baslik: 'İlgili kişi',
        ikon: Icons.assignment_ind_outlined,
        cocuk: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _talepSec,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Talep eden',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: bagli
                      ? IconButton(
                          tooltip: 'Talep bağlantısını kaldır',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _kayitsiz,
                        )
                      : const Icon(Icons.arrow_drop_down_rounded),
                ),
                child: Text(
                  bagli
                      ? trBuyuk(_talepAdi)
                      : 'Kayıtlı talepten seç (isteğe bağlı)',
                  style: tema.textTheme.bodyLarge?.copyWith(
                    color: bagli ? null : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (!bagli) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _serbestAd,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Kayıtsız kişi',
                  hintText: 'Talep kaydı olmayan biri için adını yazın',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
            ],
            if (bagli && _alanlarCevrimdisi)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Bağlantı yok: şablona yalnızca ad, T.C. kimlik no ve telefon aktarıldı.',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Sayın',
        ikon: Icons.person_outline_rounded,
        cocuk: Column(
          children: [
            TextFormField(
              controller: _kisi,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Kişi ya da kurum *',
                prefixIcon: const Icon(Icons.badge_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Bakanlık / kurum listesinden seç',
                  icon: const Icon(Icons.account_balance_outlined),
                  onPressed: _kurumSec,
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Yazının yöneltildiği kişi ya da kurum zorunludur'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _unvan,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ünvan',
                prefixIcon: Icon(Icons.work_outline_rounded),
              ),
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Yazı metni',
        ikon: Icons.article_outlined,
        cocuk: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_ref.sablonlar.isNotEmpty) ...[
              DropdownButtonFormField<int>(
                initialValue: _sablonNo == 0 ? null : _sablonNo,
                isExpanded: true,
                hint: const Text('Seçiniz'),
                decoration: const InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  labelText: 'Hazır şablon',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                items: [
                  for (final s in _ref.sablonlar)
                    DropdownMenuItem(value: s.no, child: Text(s.adi)),
                ],
                onChanged: (v) {
                  if (v != null) _sablonSec(v);
                },
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _metin,
              minLines: 8,
              maxLines: 24,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (!_metinYaziliyor) _metinElle = true;
              },
              decoration: const InputDecoration(
                labelText: 'Metin *',
                hintText: 'Yazının metnini yazın ya da şablon seçin',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Yazı metni zorunludur'
                  : null,
            ),
            if (kalan > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$kalan boşluk doldurulmadı (…… ya da {{ALAN}}). Talep seçince bilinenler dolar; kalanları metne elle yazın.',
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_sablonHam != null && _bos == 0 && !_metinElle)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Şablondaki tüm boşluklar dolduruldu.',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_yeni && _yazisma != null && _yazisma!.icerik.contains('<'))
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
                        'Metni değiştirirseniz kalın / liste gibi biçimler sadeleşir; değiştirmezseniz korunur.',
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Görünüm',
        ikon: Icons.tune_rounded,
        cocuk: Column(
          children: [
            _anahtar('Logo ve makam başlığı', _logo, (v) => _logo = v),
            _anahtar('İmza', _imza, (v) => _imza = v),
            _anahtar(
              'İmza altında makam adı ve ünvanı',
              _imzaUnvan,
              (v) => _imzaUnvan = v,
            ),
            _anahtar(
              'İmza altında ikinci ünvan',
              _imzaUnvan2,
              (v) => _imzaUnvan2 = v,
            ),
            _anahtar(
              'Alt bilgi (telefon, e-posta, adres)',
              _altYazi,
              (v) => _altYazi = v,
            ),
          ],
        ),
      ),
      ProgramKutu(
        baslik: 'Önizleme',
        ikon: Icons.preview_outlined,
        cocuk: YazismaKagidi(
          kisi: _kisi.text,
          unvan: _unvan.text,
          metin: _metin.text,
          logo: _logo,
          imza: _imza,
          imzaUnvan: _imzaUnvan,
          imzaUnvan2: _imzaUnvan2,
          altYazi: _altYazi,
          makamLogo: widget.oturum.makamResmi,
          makamImza: widget.oturum.makamImza,
          makam: widget.oturum.ben?['makam'] as Map<String, dynamic>?,
        ),
      ),
    ];
  }

  Widget _anahtar(String etiket, bool deger, void Function(bool) yaz) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(etiket),
        value: deger,
        onChanged: (v) => setState(() => yaz(v)),
      );
}

/// "3 Kasım 2026" biçimi (şablondaki BUGUN alanı).
String yazismaGun(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Yerel taleplerden arama kutulu seçim.
class _TalepSecici extends StatefulWidget {
  const _TalepSecici({required this.depo});

  final dynamic depo;

  @override
  State<_TalepSecici> createState() => _TalepSeciciState();
}

class _TalepSeciciState extends State<_TalepSecici> {
  final _ara = TextEditingController();
  List<Talep> _liste = [];
  bool _yukleniyor = true;
  Timer? _bekle;

  @override
  void initState() {
    super.initState();
    _getir();
  }

  @override
  void dispose() {
    _bekle?.cancel();
    _ara.dispose();
    super.dispose();
  }

  Future<void> _getir() async {
    final l = await widget.depo.liste(
      arama: _ara.text.trim(),
      limit: 30,
    ) as List<Talep>;
    if (mounted) {
      setState(() {
        _liste = l;
        _yukleniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              TextField(
                controller: _ara,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Ad, telefon ya da T.C. no ile ara',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) {
                  _bekle?.cancel();
                  _bekle = Timer(const Duration(milliseconds: 250), _getir);
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _yukleniyor
                    ? const Center(child: CircularProgressIndicator())
                    : _liste.isEmpty
                    ? Center(
                        child: Text(
                          'Talep bulunamadı.',
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: tema.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _liste.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final t = _liste[i];
                          final tarih = programZamani(t.v['tarih']);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.adBuyuk),
                            subtitle: Text(
                              [
                                if (tarih != null) yazismaTarihYaz(tarih),
                                if (t.telefon.isNotEmpty) t.telefon,
                              ].join(' · '),
                            ),
                            onTap: () => Navigator.pop(context, t),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bakanlık / kurum / kişi önerileri (sunucudan; çevrimdışıyken sebebi söyler).
class _KurumSecici extends StatefulWidget {
  const _KurumSecici({required this.api});

  final ApiIstemci api;

  @override
  State<_KurumSecici> createState() => _KurumSeciciState();
}

class _KurumSeciciState extends State<_KurumSecici> {
  final _ara = TextEditingController();
  List<Map<String, dynamic>> _liste = [];
  bool _yukleniyor = true;
  String? _hata;
  Timer? _bekle;

  @override
  void initState() {
    super.initState();
    _getir();
  }

  @override
  void dispose() {
    _bekle?.cancel();
    _ara.dispose();
    super.dispose();
  }

  Future<void> _getir() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final v = await widget.api.get(
        'yazismalar/kurum-ara?q=${Uri.encodeQueryComponent(_ara.text.trim())}',
      );
      if (!mounted) return;
      setState(() {
        _liste = [
          for (final x in (v['liste'] as List? ?? const []))
            Map<String, dynamic>.from(x as Map),
        ];
        _yukleniyor = false;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = e.agHatasi
            ? 'Liste için internet bağlantısı gerekir. Adı doğrudan yazabilirsiniz.'
            : e.mesaj;
        _yukleniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              TextField(
                controller: _ara,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Bakanlık, kurum ya da kişi ara',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) {
                  _bekle?.cancel();
                  _bekle = Timer(const Duration(milliseconds: 300), _getir);
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _yukleniyor
                    ? const Center(child: CircularProgressIndicator())
                    : _hata != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_hata!, textAlign: TextAlign.center),
                        ),
                      )
                    : _liste.isEmpty
                    ? Center(
                        child: Text(
                          'Kayıt bulunamadı.',
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: tema.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _liste.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final k = _liste[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${k['ad']}'),
                            subtitle: Text(
                              [
                                if ('${k['unvan']}'.isNotEmpty) '${k['unvan']}',
                                if ('${k['kurum']}'.isNotEmpty) '${k['kurum']}',
                              ].join(' · '),
                            ),
                            onTap: () => Navigator.pop(context, k),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
