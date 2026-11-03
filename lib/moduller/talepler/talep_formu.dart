import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../veri/adres_servisi.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/talep.dart';
import '../../veri/talep_deposu.dart';
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/alanlar.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/modul_hero.dart';

/// Yeni talep ya da var olanın düzenlenmesi: v7 web formundaki tüm alan ve seçenekler.
/// Kaydet yerel veritabanına yazar ve gönderim kuyruğuna alır; ağ beklenmez. SMS, rehbere kayıt ve dosyalar bağlantı gelince işlenir.
class TalepFormu extends StatefulWidget {
  const TalepFormu({super.key, required this.veri, this.yerelId});

  final VeriKatmani veri;
  final int? yerelId;

  @override
  State<TalepFormu> createState() => _TalepFormuState();
}

class _TalepFormuState extends State<TalepFormu> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{
    for (final k in [
      'talep_eden',
      'tcno',
      'telefon',
      'icerik',
      'yapilan_islem',
      'mulakat_yeri',
      'ilgili_kurum',
      'referans',
      'referans_telefon',
    ])
      k: TextEditingController(),
  };

  Talep? _talep;
  KuyrukOp? _sorun;
  Map<String, dynamic> _ek =
      {}; // sunucudan alınmış ayrıntı önbelleği (rehber durumu, dosyalar...)
  Map<String, dynamic> _ref =
      {}; // rehber kategorileri, varsayılan il, SMS hazır mı
  Map<int, ({String adi, String? renk})> _durumlar = {};
  Map<int, String> _kategoriler = {};

  int? _il, _ilce, _semt, _mahalle, _katno, _durum;
  String? _tarih, _mulakat, _hatirTarih;
  int _hatirlatici = 0; // 0 seçilmedi, 1 evet, 2 hayır
  int _sms = 0; // 0 seçilmedi, 1 gönder, 2 gönderme
  bool _smsKisi = true, _smsReferans = true;
  int? _rehberKayit; // null seçilmedi, 1 evet, 0 hayır
  int? _rehberKategori;
  bool _kara = false;
  bool _karaDokunuldu = false;
  bool _rehberdeVar = false; // seçilen/var olan kişi rehberde kayıtlı
  final List<SecilenDosya> _yeniDosyalar = [];
  final Set<String> _silinecekDosyalar = {};
  List<KuyrukOp> _bekleyenDosyaIslemleri = [];

  bool _hazir = false;
  bool _kaydediliyor = false;

  TalepDeposu get _depo => widget.veri.talepler;
  AdresServisi get _adres => widget.veri.adres;
  bool get _yeni => widget.yerelId == null;

  @override
  void initState() {
    super.initState();
    _c['referans']!.addListener(() => setState(() {}));
    _c['referans_telefon']!.addListener(() => setState(() {}));
    _yukle();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _bugun() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _yukle() async {
    _durumlar = await _depo.durumlar();
    _kategoriler = await _depo.kategoriler();
    _ref = await _depo.referansEk();
    if (!_yeni) {
      _talep = await _depo.getir(widget.yerelId!);
      _sorun = (await _depo.sorunlular())[widget.yerelId];
      _bekleyenDosyaIslemleri = await _depo.dosyaIslemleri(widget.yerelId!);
      final no = _talep?.no;
      if (no != null) {
        _ek = await _depo.ekOku(no) ?? {};
        // güncel rehber/dosya bilgisini arkadan yenile (ağ yoksa saklı olan kullanılır)
        widget.veri.motor
            .ayrintiGetir(no)
            .then((v) {
              if (mounted) setState(() => _ek = v);
            })
            .catchError((_) {});
      }
    }
    final t = _talep;
    for (final k in _c.keys) {
      final ham = t?.s(k) ?? '';
      _c[k]!.text = (k == 'icerik' || k == 'yapilan_islem')
          ? htmlDuz(ham)
          : (k == 'telefon' || k == 'referans_telefon')
          ? telefonBicimle(ham)
          : ham;
    }
    _il =
        _pozitif(t?.v['il']) ??
        (_yeni ? _pozitif(_ref['varsayilan_il']) : null);
    _ilce = _pozitif(t?.v['ilce']);
    _semt = _pozitif(t?.v['semt']);
    _mahalle = _pozitif(t?.v['mahalle']);
    _durum = _durumlar.containsKey(t?.durum)
        ? t!.durum
        : null; // yeni kayıtta "Seçiniz"
    _katno = _kategoriler.containsKey(t?.katno) ? t!.katno : null;
    _tarih = t?.tarih ?? _bugun();
    _mulakat = t?.mulakatTarihi;
    _hatirlatici = t == null
        ? 0
        : (t.i('hatirlatici') == 1 ? 1 : (t.i('hatirlatici') == 2 ? 2 : 0));
    _hatirTarih = _hatirlatici == 1
        ? (t?.v['hatirlatici_tarih'] as String?)
        : null;
    _hatirTarih ??= _bugun();
    final rehber = _ek['rehber'];
    if (rehber is Map) {
      _rehberdeVar = rehber['var'] == true;
      _kara = rehber['kara_liste'] == true;
    }
    if (mounted) setState(() => _hazir = true);
    _adlariCoz();
  }

  int? _pozitif(Object? v) {
    final n = (v is num) ? v.toInt() : int.tryParse('${v ?? ''}');
    return (n == null || n <= 0) ? null : n;
  }

  bool get _mulakatGoster => RegExp(
    'mülakat',
    caseSensitive: false,
  ).hasMatch(_kategoriler[_katno] ?? '');

  /// Zengin metin (web) alanı değişmediyse özgün HTML korunur; değiştiyse düz metinden basit paragraflara çevrilir.
  String _htmlAlan(String k) {
    final ozgun = _talep?.s(k) ?? '';
    final yeni = _c[k]!.text;
    return htmlDuz(ozgun) == yeni.trim() ? ozgun : duzHtml(yeni);
  }

  Future<void> _tarihSec(String? mevcut, void Function(String) ata) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(mevcut ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(
      () => ata(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      ),
    );
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Kırmızı işaretli alanları doldurun.')),
        );
      return;
    }
    // Web kuralları: yeni kayıtta SMS tercihi ve (kişi rehberde yoksa) rehber tercihi zorunlu
    if (_yeni && _sms == 0) {
      _uyar('SMS için "Gönder" ya da "Gönderme" seçin.');
      return;
    }
    if (!_rehberdeVar && !_kara && _yeni && _rehberKayit == null) {
      _uyar('Rehbere kaydet seçeneğini belirleyin.');
      return;
    }
    if (_rehberKayit == 1 && _rehberKategori == null) {
      _uyar('Rehber kategorisini seçin.');
      return;
    }
    setState(() => _kaydediliyor = true);

    final alanlar = <String, Object?>{
      ...?_talep?.alanlar(),
      'il': _il ?? 0,
      'ilce': _ilce ?? 0,
      'semt': _semt ?? 0,
      'mahalle': _mahalle ?? 0,
      'talep_eden': _c['talep_eden']!.text.trim(),
      'tcno': _c['tcno']!.text.trim(),
      'telefon': _c['telefon']!.text.trim(),
      'katno': _katno ?? 0,
      'durum': _durum ?? 0,
      'tarih': _tarih,
      'icerik': _htmlAlan('icerik'),
      'yapilan_islem': _htmlAlan('yapilan_islem'),
      'mulakat_tarihi': _mulakatGoster ? _mulakat : null,
      'mulakat_yeri': _mulakatGoster ? _c['mulakat_yeri']!.text.trim() : '',
      'ilgili_kurum': _c['ilgili_kurum']!.text.trim(),
      'referans': _c['referans']!.text.trim(),
      'referans_telefon': _c['referans_telefon']!.text.trim(),
      'hatirlatici': _hatirlatici,
      'hatirlatici_tarih': _hatirlatici == 1 ? _hatirTarih : null,
    };
    final referansVar =
        _c['referans']!.text.trim().isNotEmpty &&
        _c['referans_telefon']!.text.trim().isNotEmpty;
    final ekstra = <String, Object?>{
      'sms_gonder': _sms,
      if (_sms == 1) 'sms_talep_eden': _smsKisi ? 1 : 0,
      if (_sms == 1) 'sms_referans': (_smsReferans && referansVar) ? 1 : 0,
      // Rehber alanları yalnızca kullanıcı bir seçim yaptıysa ya da kayıt yeniyse gönderilir (mevcut durum bilinmiyorsa dokunulmaz)
      if (!_rehberdeVar && _rehberKayit != null)
        'rehber_kayit': _kara ? 1 : _rehberKayit,
      if (!_rehberdeVar &&
          (_rehberKayit == 1 || _kara) &&
          _rehberKategori != null)
        'rehber_kategori': _rehberKategori,
      if (_yeni || _karaDokunuldu || _kara) 'kara_liste': _kara ? 1 : 0,
    };

    final id = await _depo.kaydet(
      alanlar,
      yerelId: widget.yerelId,
      ekstra: ekstra,
    );
    // Dosyalar: eklenenler gönderim kuyruğuna, silinecek sunucu dosyaları silme kuyruğuna
    for (final d in _yeniDosyalar) {
      await _depo.dosyaEkle(id, yol: d.yol, ad: d.ad, boyut: d.boyut);
    }
    final no = _talep?.no;
    if (no != null) {
      for (final ad in _silinecekDosyalar) {
        await _depo.sunucuDosyasiniSil(id, no, ad);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Kaydedildi. Bağlantı varsa hemen gönderilir.'),
        ),
      );
  }

  void _uyar(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Talep silinsin mi?'),
        content: const Text(
          'Talep çöp kutusuna taşınır (web panelinden geri alınabilir).',
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
    await _depo.sil(widget.yerelId!);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ------------------------------------------------------------------ arayüz

  @override
  Widget build(BuildContext context) {
    final cakisma = _sorun?.durum == 'cakisma';
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            baslik: _yeni ? 'Yeni talep' : 'Talebi düzenle',
            altBaslik: _yeni
                ? 'Bilgileri girip kaydedin'
                : (_talep?.adBuyuk ?? ''),
            eylemler: [
              if (!_yeni)
                IconButton(
                  tooltip: 'Sil',
                  onPressed: _hazir ? _sil : null,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          Expanded(
            child: !_hazir
                ? const Center(child: CircularProgressIndicator())
                : SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
                          children: [
                            if (_sorun != null)
                              _SorunKutusu(
                                op: _sorun!,
                                talep: _talep,
                                depo: _depo,
                                bitti: () => Navigator.of(context).pop(),
                              ),
                            if (!cakisma)
                              Form(
                                key: _form,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _bolumler(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: !_hazir || cakisma
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _kaydediliyor ? null : _kaydet,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Kaydet'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _bolum(String baslik, IconData ikon, List<Widget> cocuklar) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: tema.colorScheme.primary.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      ikon,
                      size: 17,
                      color: tema.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    baslik,
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ..._araya(cocuklar, 14),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _araya(List<Widget> l, double bosluk) => [
    for (var i = 0; i < l.length; i++) ...[
      if (i > 0) SizedBox(height: bosluk),
      l[i],
    ],
  ];

  String? _zorunlu(String? v, String ad) =>
      (v == null || v.trim().isEmpty) ? '$ad zorunlu' : null;

  String? _telefonKontrol(String? v, {bool zorunlu = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return zorunlu ? 'Telefon zorunlu' : null;
    return telefonTam(t) ? null : 'Telefonu tam girin: 0(5xx) xxx xx xx';
  }

  List<Widget> _bolumler() {
    final tema = Theme.of(context);
    final referansVar =
        _c['referans']!.text.trim().isNotEmpty &&
        _c['referans_telefon']!.text.trim().isNotEmpty;
    final rehberKategorileri = [
      for (final x in (_ref['rehber_kategorileri'] as List? ?? const []))
        SecimOgesi<int>((x as Map)['no'] as int, x['adi'] as String),
    ];

    return [
      // ---- Talep eden
      _bolum('Talep eden', Icons.person_outline, [
        OneriAlani<Map<String, Object?>>(
          controller: _c['talep_eden']!,
          etiket: 'Ad soyad *',
          ikon: Icons.person_outline,
          buyukHarf: true,
          validator: (v) => _zorunlu(v, 'Talep eden'),
          oneriler: (q) async {
            final yerel = await _depo.yerelOneriler('kisi', q);
            final liste = <Map<String, Object?>>[];
            try {
              final v = await widget.veri.motor.api.get(
                'rehber/ara?kelime=${Uri.encodeQueryComponent(q)}',
              );
              for (final x in (v['liste'] as List? ?? const [])) {
                final m = x as Map;
                liste.add({
                  'ad': m['adi'],
                  'telefon': m['telefon'],
                  'rehber': true,
                  'kara': m['kara_liste'] == true,
                  'kategori': m['kategori'],
                });
              }
            } on ApiHata {
              // çevrimdışı: yalnızca yerel öneriler
            }
            final gorulen = liste
                .map((e) => '${e['ad']}|${e['telefon']}')
                .toSet();
            for (final y in yerel) {
              if (!gorulen.contains('${y['ad']}|${y['telefon']}')) {
                liste.add({
                  'ad': y['ad'],
                  'telefon': y['telefon'],
                  'rehber': false,
                });
              }
            }
            return liste;
          },
          metin: (o) => '${o['ad']}',
          altMetin: (o) => [
            telefonBicimle('${o['telefon'] ?? ''}'),
            if (o['rehber'] == true) 'rehberde',
            if (o['kara'] == true) 'KARA LİSTE',
          ].where((e) => e.isNotEmpty).join(' · '),
          sec: (o) => setState(() {
            _c['telefon']!.text = telefonBicimle('${o['telefon'] ?? ''}');
            if (o['rehber'] == true) {
              _rehberdeVar = true;
              _kara = o['kara'] == true;
            }
          }),
        ),
        TextFormField(
          controller: _c['tcno'],
          keyboardType: TextInputType.number,
          maxLength: 11,
          decoration: const InputDecoration(
            labelText: 'T.C. kimlik no',
            prefixIcon: Icon(Icons.badge_outlined),
            counterText: '',
          ),
          validator: (v) =>
              (v == null || v.isEmpty || RegExp(r'^\d{11}$').hasMatch(v))
              ? null
              : '11 haneli olmalı',
        ),
        TextFormField(
          controller: _c['telefon'],
          keyboardType: TextInputType.phone,
          inputFormatters: [TelefonMaskesi()],
          decoration: const InputDecoration(
            labelText: 'Telefon *',
            prefixIcon: Icon(Icons.phone_outlined),
            hintText: '0(5xx) xxx xx xx',
          ),
          validator: (v) => _telefonKontrol(v, zorunlu: true),
        ),
      ]),

      // ---- Konum
      _bolum('Konum', Icons.location_on_outlined, [
        SecimAlani<int>(
          key: ValueKey('il$_il'),
          etiket: 'İl *',
          ikon: Icons.public_outlined,
          initialValue: _il,
          gorunenAd: _adAra(_ilAdlari, _il),
          liste: () async => [
            for (final o in await _adres.iller()) SecimOgesi(o.id, o.ad),
          ],
          degisti: (v) => _adresDegisti(() {
            if (v != _il) _ilce = _semt = _mahalle = null;
            _il = v;
          }),
          validator: (v) => v == null ? 'İl seçin' : null,
          temizlenebilir: false,
        ),
        SecimAlani<int>(
          key: ValueKey('ilce$_il$_ilce'),
          etiket: 'İlçe *',
          ikon: Icons.map_outlined,
          initialValue: _ilce,
          etkin: _il != null,
          gorunenAd: _adAra(_ilceAdlari, _ilce),
          liste: () async => [
            for (final o in await _adres.ilceler(_il!)) SecimOgesi(o.id, o.ad),
          ],
          degisti: (v) => _adresDegisti(() {
            if (v != _ilce) _semt = _mahalle = null;
            _ilce = v;
          }),
          validator: (v) => v == null ? 'İlçe seçin' : null,
          temizlenebilir: false,
        ),
        SecimAlani<int>(
          key: ValueKey('semt$_ilce$_semt'),
          etiket: 'Semt',
          ikon: Icons.holiday_village_outlined,
          initialValue: _semt,
          etkin: _ilce != null,
          gorunenAd: _adAra(_semtAdlari, _semt),
          liste: () async => [
            for (final o in await _adres.semtler(_ilce!))
              SecimOgesi(o.id, o.ad),
          ],
          degisti: (v) => _adresDegisti(() {
            if (v != _semt) _mahalle = null;
            _semt = v;
          }),
        ),
        SecimAlani<int>(
          key: ValueKey('mahalle$_semt$_mahalle'),
          etiket: 'Mahalle',
          ikon: Icons.home_work_outlined,
          initialValue: _mahalle,
          etkin: _semt != null,
          gorunenAd: _adAra(_mahalleAdlari, _mahalle),
          liste: () async => [
            for (final o in await _adres.mahalleler(_semt!))
              SecimOgesi(o.id, o.ad),
          ],
          degisti: (v) => _adresDegisti(() => _mahalle = v),
        ),
      ]),

      // ---- Talep bilgisi
      _bolum('Talep bilgisi', Icons.description_outlined, [
        SecimAlani<int>(
          key: ValueKey('kat$_katno'),
          etiket: 'Kategori *',
          ikon: Icons.category_outlined,
          initialValue: _katno,
          gorunenAd: _kategoriler[_katno],
          liste: () async => [
            for (final e in _kategoriler.entries) SecimOgesi(e.key, e.value),
          ],
          degisti: (v) => setState(() => _katno = v),
          validator: (v) => v == null ? 'Kategori seçin' : null,
          temizlenebilir: false,
        ),
        SecimAlani<int>(
          key: ValueKey('durum$_durum'),
          etiket: 'Durum *',
          ikon: Icons.flag_outlined,
          initialValue: _durum,
          gorunenAd: _durumlar[_durum]?.adi,
          liste: () async => [
            for (final e in _durumlar.entries) SecimOgesi(e.key, e.value.adi),
          ],
          degisti: (v) => setState(() => _durum = v),
          validator: (v) => v == null ? 'Durum seçin' : null,
          temizlenebilir: false,
        ),
        _TarihAlani(
          etiket: 'Talep tarihi *',
          deger: _tarih,
          sec: () => _tarihSec(_tarih, (v) => _tarih = v),
        ),
        if (_mulakatGoster) ...[
          _TarihAlani(
            etiket: 'Mülakat tarihi',
            deger: _mulakat,
            sec: () => _tarihSec(_mulakat, (v) => _mulakat = v),
            temizle: () => setState(() => _mulakat = null),
          ),
          TextFormField(
            controller: _c['mulakat_yeri'],
            decoration: const InputDecoration(
              labelText: 'Mülakat yeri',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
        ],
        TextFormField(
          controller: _c['icerik'],
          minLines: 5,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'İçerik *',
            alignLabelWithHint: true,
          ),
          validator: (v) => _zorunlu(v, 'İçerik'),
        ),
        TextFormField(
          controller: _c['yapilan_islem'],
          minLines: 3,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Yapılan işlem (isteğe bağlı)',
            alignLabelWithHint: true,
          ),
        ),
      ]),

      // ---- Kurum ve referans
      _bolum('Kurum ve referans', Icons.account_balance_outlined, [
        OneriAlani<String>(
          controller: _c['ilgili_kurum']!,
          etiket: 'İlgili kurum',
          ikon: Icons.apartment_outlined,
          oneriler: (q) async {
            final liste = <String>[];
            try {
              final v = await widget.veri.motor.api.get(
                'talepler/kurum-ara?kelime=${Uri.encodeQueryComponent(q)}',
              );
              liste.addAll([
                for (final x in (v['liste'] as List? ?? const [])) '$x',
              ]);
            } on ApiHata {
              // çevrimdışı
            }
            for (final y in await _depo.yerelOneriler('kurum', q)) {
              final a = '${y['ad']}';
              if (!liste.contains(a)) liste.add(a);
            }
            return liste;
          },
          metin: (o) => o,
          sec: (_) {},
        ),
        OneriAlani<Map<String, Object?>>(
          controller: _c['referans']!,
          etiket: 'Referans',
          ikon: Icons.supervisor_account_outlined,
          buyukHarf: true,
          oneriler: (q) => _depo.yerelOneriler('referans', q),
          metin: (o) => '${o['ad']}',
          altMetin: (o) => telefonBicimle('${o['telefon'] ?? ''}'),
          sec: (o) => setState(
            () => _c['referans_telefon']!.text = telefonBicimle(
              '${o['telefon'] ?? ''}',
            ),
          ),
        ),
        TextFormField(
          controller: _c['referans_telefon'],
          keyboardType: TextInputType.phone,
          inputFormatters: [TelefonMaskesi()],
          decoration: const InputDecoration(
            labelText: 'Referans telefonu',
            prefixIcon: Icon(Icons.phone_forwarded_outlined),
            hintText: '0(5xx) xxx xx xx',
          ),
          validator: (v) => _telefonKontrol(v),
        ),
      ]),

      // ---- Bildirim ve hatırlatma
      _bolum('Bildirim ve hatırlatma', Icons.notifications_active_outlined, [
        _Etiketli(
          etiket: 'SMS${_yeni ? ' *' : ''}',
          cocuk: SegmentedButton<int>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 1, label: Text('Gönder')),
              ButtonSegment(value: 2, label: Text('Gönderme')),
            ],
            selected: {if (_sms != 0) _sms},
            onSelectionChanged: (s) =>
                setState(() => _sms = s.isEmpty ? 0 : s.first),
          ),
          not: _ref['sms_hazir'] == false && _sms == 1
              ? 'Bu makamda SMS ayarları tanımlı değil; SMS gönderilemeyecek.'
              : (_sms == 1 ? 'SMS, talep sunucuya ulaşınca gönderilir.' : null),
        ),
        if (_sms == 1)
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Talep eden'),
                selected: _smsKisi,
                onSelected: (v) => setState(() => _smsKisi = v),
              ),
              FilterChip(
                label: const Text('Referans'),
                selected: _smsReferans && referansVar,
                onSelected: referansVar
                    ? (v) => setState(() => _smsReferans = v)
                    : null,
                tooltip: referansVar
                    ? null
                    : 'Referans adı ve telefonu girilince seçilebilir',
              ),
            ],
          ),
        _Etiketli(
          etiket: 'Hatırlatıcı',
          cocuk: SegmentedButton<int>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 1, label: Text('Evet')),
              ButtonSegment(value: 2, label: Text('Hayır')),
            ],
            selected: {if (_hatirlatici != 0) _hatirlatici},
            onSelectionChanged: (s) =>
                setState(() => _hatirlatici = s.isEmpty ? 0 : s.first),
          ),
        ),
        if (_hatirlatici == 1)
          _TarihAlani(
            etiket: 'Hatırlatıcı tarihi',
            deger: _hatirTarih,
            sec: () => _tarihSec(_hatirTarih, (v) => _hatirTarih = v),
          ),
      ]),

      // ---- Telefon rehberi
      _bolum('Telefon rehberi', Icons.contacts_outlined, [
        if (_rehberdeVar)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tema.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: tema.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Bu kişi daha önce telefon rehberine kaydedilmiş.',
                  ),
                ),
              ],
            ),
          )
        else ...[
          _Etiketli(
            etiket: 'Rehbere kaydet${_yeni ? ' *' : ''}',
            cocuk: SegmentedButton<int>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Evet')),
                ButtonSegment(value: 0, label: Text('Hayır')),
              ],
              selected: {if (_kara) 1 else ?_rehberKayit},
              onSelectionChanged: _kara
                  ? null
                  : (s) => setState(
                      () => _rehberKayit = s.isEmpty ? null : s.first,
                    ),
            ),
            not: _kara
                ? 'Kara listeye alınan kişi rehbere de kaydedilir.'
                : null,
          ),
          if (_rehberKayit == 1 || _kara)
            SecimAlani<int>(
              key: ValueKey('rkat$_rehberKategori'),
              etiket: 'Rehber kategorisi *',
              ikon: Icons.folder_shared_outlined,
              initialValue: _rehberKategori,
              gorunenAd: [
                for (final o in rehberKategorileri)
                  if (o.deger == _rehberKategori) o.ad,
              ].firstOrNull,
              liste: () async => rehberKategorileri,
              degisti: (v) => setState(() => _rehberKategori = v),
              validator: (v) => v == null ? 'Rehber kategorisi seçin' : null,
              temizlenebilir: false,
            ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _kara,
          onChanged: (v) => setState(() {
            _kara = v;
            _karaDokunuldu = true;
          }),
          title: const Text(
            'Kara listeye ekle',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Bu kişiyi işaretler; rehbere de kaydedilir.'),
        ),
      ]),

      // ---- Ek dosyalar
      _bolum('Ek dosyalar', Icons.attach_file_rounded, _ekDosyalar()),
      const SizedBox(height: 60),
    ];
  }

  void _adresDegisti(VoidCallback f) {
    setState(f);
    _adlariCoz();
  }

  // Adlar: çevrimdışıyken bile gösterilebilsin diye seçili öğenin adını önbellekten bulur.
  final Map<int, String> _ilAdlari = {},
      _ilceAdlari = {},
      _semtAdlari = {},
      _mahalleAdlari = {};

  String? _adAra(Map<int, String> harita, int? id) =>
      id == null ? null : (harita[id] ?? '#$id');

  Future<void> _adlariCoz() async {
    try {
      if (_il != null) {
        for (final o in await _adres.iller()) {
          _ilAdlari[o.id] = o.ad;
        }
        if (_ilce != null) {
          for (final o in await _adres.ilceler(_il!)) {
            _ilceAdlari[o.id] = o.ad;
          }
        }
      }
      if (_ilce != null && _semt != null) {
        for (final o in await _adres.semtler(_ilce!)) {
          _semtAdlari[o.id] = o.ad;
        }
      }
      if (_semt != null && _mahalle != null) {
        for (final o in await _adres.mahalleler(_semt!)) {
          _mahalleAdlari[o.id] = o.ad;
        }
      }
    } on ApiHata {
      // çevrimdışı ve önbellekte yok: kimlik numarası gösterilir
    }
    if (mounted) setState(() {});
  }

  List<Widget> _ekDosyalar() {
    final sunucuDosyalari = [
      for (final d in (_ek['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(d as Map),
    ];
    final no = _talep?.no;
    final bekleyenSilmeler = {
      for (final o in _bekleyenDosyaIslemleri.where(
        (o) => o.tur == 'dosya_sil',
      ))
        '${o.govde['ad']}',
    };
    return [
      for (final d in sunucuDosyalari)
        if (!_silinecekDosyalar.contains(d['ad']) &&
            !bekleyenSilmeler.contains(d['ad']))
          DosyaSatiri(
            ad: '${d['goruntu']}',
            boyut: d['boyut'] as int?,
            tikla: no == null
                ? null
                : () => sunucuDosyasiniAc(
                    context,
                    widget.veri.motor.api,
                    no,
                    '${d['ad']}',
                    '${d['goruntu']}',
                  ),
            kaldir: () => setState(() => _silinecekDosyalar.add('${d['ad']}')),
          ),
      for (final o in _bekleyenDosyaIslemleri.where((o) => o.tur == 'dosya'))
        DosyaSatiri(
          ad: '${o.govde['ad']}',
          boyut: (o.govde['boyut'] as num?)?.toInt(),
          etiket: 'gönderilecek',
          kaldir: () async {
            await _depo.dosyaIsleminiIptalEt(o);
            _bekleyenDosyaIslemleri = await _depo.dosyaIslemleri(
              widget.yerelId!,
            );
            if (mounted) setState(() {});
          },
        ),
      for (final d in _yeniDosyalar)
        DosyaSatiri(
          ad: d.ad,
          boyut: d.boyut,
          etiket: 'kaydedilince gönderilecek',
          kaldir: () => setState(() => _yeniDosyalar.remove(d)),
        ),
      if (sunucuDosyalari.isEmpty &&
          _yeniDosyalar.isEmpty &&
          _bekleyenDosyaIslemleri.isEmpty)
        Text(
          'Ek dosya yok.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      DosyaEkleDugmeleri(
        secildi: (l) => setState(() => _yeniDosyalar.addAll(l)),
      ),
    ];
  }
}

class _Etiketli extends StatelessWidget {
  const _Etiketli({required this.etiket, required this.cocuk, this.not});

  final String etiket;
  final Widget cocuk;
  final String? not;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiket,
          style: tema.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: cocuk),
        if (not != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              not!,
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _TarihAlani extends StatelessWidget {
  const _TarihAlani({
    required this.etiket,
    required this.deger,
    required this.sec,
    this.temizle,
  });

  final String etiket;
  final String? deger;
  final VoidCallback sec;
  final VoidCallback? temizle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: sec,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiket,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: (temizle != null && deger != null)
              ? IconButton(icon: const Icon(Icons.clear), onPressed: temizle)
              : null,
        ),
        child: Text(deger == null ? 'Seçilmedi' : (uzunTarih(deger) ?? deger!)),
      ),
    );
  }
}

/// Çakışma ya da gönderim hatası olan kayıt için açıklama ve çözüm düğmeleri.
class _SorunKutusu extends StatelessWidget {
  const _SorunKutusu({
    required this.op,
    required this.talep,
    required this.depo,
    required this.bitti,
  });

  final KuyrukOp op;
  final Talep? talep;
  final TalepDeposu depo;
  final VoidCallback bitti;

  static const _etiketler = {
    'talep_eden': 'Talep eden',
    'telefon': 'Telefon',
    'tcno': 'T.C. kimlik no',
    'durum': 'Durum',
    'katno': 'Kategori',
    'icerik': 'İçerik',
    'yapilan_islem': 'Yapılan işlem',
    'mulakat_tarihi': 'Mülakat tarihi',
    'mulakat_yeri': 'Mülakat yeri',
    'referans': 'Referans',
    'referans_telefon': 'Referans telefonu',
    'ilgili_kurum': 'İlgili kurum',
    'tarih': 'Tarih',
    'hatirlatici': 'Hatırlatıcı',
    'hatirlatici_tarih': 'Hatırlatıcı tarihi',
    'il': 'İl',
    'ilce': 'İlçe',
    'semt': 'Semt',
    'mahalle': 'Mahalle',
  };

  String _goster(String k, Object? v) {
    if (v == null || '$v'.isEmpty) return '—';
    if (k == 'icerik' || k == 'yapilan_islem') return htmlDuz('$v');
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cakisma = op.durum == 'cakisma';
    final fark = <Widget>[];
    if (cakisma && talep != null && op.sunucu != null) {
      final sunucu = op.sunucu!;
      for (final k in talepAlanlari) {
        final benim = talep!.v[k];
        final onun = sunucu[k];
        if ('${benim ?? ''}' != '${onun ?? ''}' && _etiketler.containsKey(k)) {
          fark.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_etiketler[k]!, style: tema.textTheme.labelLarge),
                  Text('Siz: ${_goster(k, benim)}'),
                  Text('Sunucuda: ${_goster(k, onun)}'),
                ],
              ),
            ),
          );
        }
      }
    }
    return Card(
      color: cakisma
          ? tema.colorScheme.tertiaryContainer
          : tema.colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cakisma ? 'Çakışma' : 'Gönderilemedi',
              style: tema.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              cakisma
                  ? 'Bu talep siz çevrimdışıyken başka biri tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
                  : op.mesaj,
            ),
            ...fark,
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (cakisma) ...[
                  FilledButton(
                    onPressed: () async {
                      await depo.cakismaBenimkiniGonder(op);
                      bitti();
                    },
                    child: const Text('Benimkini gönder'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await depo.cakismaSunucuyuAl(op);
                      bitti();
                    },
                    child: const Text('Sunucudakini al'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () async {
                      await depo.islemiIptalEt(op);
                      bitti();
                    },
                    child: const Text('Değişiklikten vazgeç'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
