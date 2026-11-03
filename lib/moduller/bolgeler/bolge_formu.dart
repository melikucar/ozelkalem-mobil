import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../diger/modul_hero.dart';
import '../../veri/adres_servisi.dart';
import '../../veri/bolge.dart';
import '../../veri/bolge_deposu.dart';
import '../../veri/veri_katmani.dart';
import '../programlar/program_ortak.dart';

/// Yeni bölge / düzenleme (web "Bölge ekle" formunun karşılığı): ilçe-semt-mahalle seçimi ve bölümlere ayrılmış bilgi alanları.
/// Kayıt önce cihaza yazılır, bağlantı olunca sunucuya gider.
class BolgeFormu extends StatefulWidget {
  const BolgeFormu({super.key, required this.veri, this.yerelId});

  final VeriKatmani veri;

  /// Doluysa düzenleme, boşsa yeni kayıt.
  final int? yerelId;

  @override
  State<BolgeFormu> createState() => _BolgeFormuState();
}

class _BolgeFormuState extends State<BolgeFormu> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {
    for (final k in bolgeBilgiAnahtarlari) k: TextEditingController(),
  };

  Bolge? _kayit;
  BolgeReferans _ref = BolgeReferans({});
  bool _hazir = false;
  bool _kaydediliyor = false;
  String? _hata;

  int _il = 0;
  List<AdresOgesi> _iller = [];
  List<AdresOgesi> _ilceler = [];
  List<AdresOgesi> _semtler = [];
  List<AdresOgesi> _mahalleler = [];
  int _ilce = 0;
  int _semt = 0;
  int _mahalle = 0;
  bool _adresHata = false;

  BolgeDeposu get _depo => widget.veri.bolgeler;
  AdresServisi get _adres => widget.veri.adres;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final ref = BolgeReferans(await _depo.referans());
    Bolge? b;
    if (!_yeni) b = await _depo.getir(widget.yerelId!);
    _il = (b?.v['il'] as int?) ?? 0;
    if (_il == 0) _il = ref.varsayilanIl;
    if (b != null) {
      final bilgi = b.bilgi;
      for (final k in bolgeBilgiAnahtarlari) {
        _c[k]!.text = bilgi[k] ?? '';
      }
      _ilce = b.ilce;
      _semt = b.semt;
      _mahalle = b.mahalle;
    }
    try {
      if (_il == 0) _iller = await _adres.iller();
      if (_il != 0) _ilceler = await _adres.ilceler(_il);
      if (_ilce != 0) _semtler = await _adres.semtler(_ilce);
      if (_semt != 0) _mahalleler = await _adres.mahalleler(_semt);
    } catch (_) {
      _adresHata = true;
    }
    if (!mounted) return;
    setState(() {
      _ref = ref;
      _kayit = b;
      _hazir = true;
    });
  }

  Future<void> _ilSecildi(int il) async {
    setState(() {
      _il = il;
      _ilce = _semt = _mahalle = 0;
      _ilceler = _semtler = _mahalleler = [];
    });
    try {
      final l = await _adres.ilceler(il);
      if (mounted) setState(() => _ilceler = l);
    } catch (_) {
      if (mounted) setState(() => _adresHata = true);
    }
  }

  Future<void> _ilceSecildi(int ilce) async {
    setState(() {
      _ilce = ilce;
      _semt = _mahalle = 0;
      _semtler = _mahalleler = [];
    });
    try {
      final l = await _adres.semtler(ilce);
      if (mounted) setState(() => _semtler = l);
    } catch (_) {
      if (mounted) setState(() => _adresHata = true);
    }
  }

  Future<void> _semtSecildi(int semt) async {
    setState(() {
      _semt = semt;
      _mahalle = 0;
      _mahalleler = [];
    });
    try {
      final l = await _adres.mahalleler(semt);
      if (mounted) setState(() => _mahalleler = l);
    } catch (_) {
      if (mounted) setState(() => _adresHata = true);
    }
  }

  String _ad(List<AdresOgesi> l, int id) {
    for (final x in l) {
      if (x.id == id) return x.ad;
    }
    return '';
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    if (_ilce == 0 || !_form.currentState!.validate()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('İlçe seçmelisiniz.')));
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      await _depo.kaydet(
        {
          'ilce': _ilce,
          'semt': _semt,
          'mahalle': _mahalle,
          for (final k in bolgeBilgiAnahtarlari) k: _c[k]!.text.trim(),
        },
        adlar: {
          'ilce': _ad(_ilceler, _ilce),
          'semt': _ad(_semtler, _semt),
          'mahalle': _ad(_mahalleler, _mahalle),
        },
        yerelId: widget.yerelId,
        il: _il,
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
            ikon: Icons.holiday_village_outlined,
            baslik: _yeni ? 'YENİ BÖLGE' : 'BÖLGEYİ DÜZENLE',
            altBaslik: _kayit?.baslik ?? 'Köy / mahalle künyesi',
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
                                  _adresKutusu(),
                                  for (final b in bolgeBolumleri) _bolum(b),
                                  if (_hata != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _hata!,
                                        style: TextStyle(
                                          color: tema.colorScheme.error,
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
            label: Text(_yeni ? 'Bölgeyi kaydet' : 'Değişiklikleri kaydet'),
          ),
        ),
      ),
    ),
  );

  Widget _secim(
    String etiket,
    List<AdresOgesi> liste,
    int deger,
    ValueChanged<int> degisti, {
    bool zorunlu = false,
  }) {
    final var_ = liste.any((x) => x.id == deger);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: var_ ? deger : null,
        decoration: InputDecoration(labelText: zorunlu ? '$etiket *' : etiket),
        items: [
          for (final x in liste)
            DropdownMenuItem(
              value: x.id,
              child: Text(x.ad, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: liste.isEmpty
            ? null
            : (v) {
                if (v != null) degisti(v);
              },
      ),
    );
  }

  Widget _adresKutusu() => ProgramKutu(
    baslik: 'Bölge',
    ikon: Icons.place_outlined,
    cocuk: Column(
      children: [
        if (_adresHata)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Adres listesi indirilemedi; bağlantı olunca tekrar deneyin.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_ref.varsayilanIl == 0 && _iller.isNotEmpty)
          _secim('İl', _iller, _il, _ilSecildi),
        _secim('İlçe', _ilceler, _ilce, _ilceSecildi, zorunlu: true),
        _secim('Semt', _semtler, _semt, _semtSecildi),
        _secim('Mahalle', _mahalleler, _mahalle, (v) {
          setState(() => _mahalle = v);
        }),
      ],
    ),
  );

  Widget _bolum(BolgeBolumu b) => ProgramKutu(
    baslik: b.ad,
    ikon: b.ikon,
    cocuk: Column(
      children: [
        for (final a in b.alanlar)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: _c[a.anahtar],
              minLines: a.coklu ? 2 : 1,
              maxLines: a.coklu ? 6 : 1,
              keyboardType: a.coklu
                  ? TextInputType.multiline
                  : a.telefon
                  ? TextInputType.phone
                  : a.sayisal
                  ? TextInputType.text
                  : TextInputType.text,
              inputFormatters: a.telefon
                  ? [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+()\-. /]'),
                      ),
                    ]
                  : null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: a.etiket),
            ),
          ),
      ],
    ),
  );
}
