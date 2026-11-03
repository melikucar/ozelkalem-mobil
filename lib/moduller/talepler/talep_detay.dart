import '../../diger/kompakt_dugme.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/api_istemci.dart';
import '../../../tema/tema.dart';
import '../../veri/yazi_formatlari.dart';
import '../../../veri/talep.dart';
import '../../../veri/talep_deposu.dart';
import '../../../veri/tarih_yardimci.dart';
import '../../../veri/veri_katmani.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/modul_hero.dart';
import 'talep_formu.dart';
import 'talepler_listesi.dart' show talepRengi;

/// Talep ayrıntısı (salt okunur): v7'deki "Talep kayıt bilgileri" penceresinin tamamı — iletişim, ikamet, içerik, kategori/durum,
/// mülakat, kurum, referans, kaydeden, ilk kayıt / son güncelleme, ek dosyalar, SMS'ler, üst yazılar, rehber durumu ve değişiklik geçmişi.
/// Sunucu ayrıntıları (kaydeden, SMS, dosyalar...) bağlantı varken indirilip saklanır; çevrimdışıyken son saklanan gösterilir.
class TalepDetay extends StatefulWidget {
  const TalepDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<TalepDetay> createState() => _TalepDetayState();
}

class _TalepDetayState extends State<TalepDetay> {
  Talep? _talep;
  KuyrukOp? _sorun;
  List<KuyrukOp> _dosyaIslemleri = [];
  Map<String, dynamic>? _ek;
  Map<int, ({String adi, String? renk})> _durumlar = {};
  Map<int, String> _kategoriler = {};
  Map<String, String> _adres = {};
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _ekHata = false;

  TalepDeposu get _depo => widget.veri.talepler;

  @override
  void initState() {
    super.initState();
    _depo.addListener(_yukle);
    _yukle();
  }

  @override
  void dispose() {
    _depo.removeListener(_yukle);
    super.dispose();
  }

  Future<void> _yukle() async {
    final t = await _depo.getir(widget.yerelId);
    final d = await _depo.durumlar();
    final k = await _depo.kategoriler();
    final s = (await _depo.sorunlular())[widget.yerelId];
    final dosyalar = await _depo.dosyaIslemleri(widget.yerelId);
    final ek = t?.no == null ? null : await _depo.ekOku(t!.no!);
    if (!mounted) return;
    if (t == null || t.silindi) {
      Navigator.of(context).maybePop(); // silindi
      return;
    }
    final ilk = !_yuklendi;
    setState(() {
      _talep = t;
      _durumlar = d;
      _kategoriler = k;
      _sorun = s;
      _dosyaIslemleri = dosyalar;
      _ek = ek;
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
    _adresAdlari(t);
  }

  /// Sunucudan tam ayrıntıyı alır (ağ yoksa sessizce saklı olanla devam eder).
  Future<void> _ekiYenile() async {
    final no = _talep?.no;
    if (no == null) return;
    setState(() {
      _ekYukleniyor = true;
      _ekHata = false;
    });
    try {
      final v = await widget.veri.motor.ayrintiGetir(no);
      if (mounted) setState(() => _ek = v);
    } on ApiHata {
      if (mounted) setState(() => _ekHata = true);
    } finally {
      if (mounted) setState(() => _ekYukleniyor = false);
    }
  }

  /// İl/ilçe/semt/mahalle adları: sunucu ayrıntısında varsa onlar, yoksa cihazdaki liste önbelleğinden.
  Future<void> _adresAdlari(Talep t) async {
    final a = <String, String>{};
    final e =
        (_ek?['adres'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? {};
    try {
      final adr = widget.veri.adres;
      final il = t.i('il'),
          ilce = t.i('ilce'),
          semt = t.i('semt'),
          mahalle = t.i('mahalle');
      String? bul(List<dynamic> l, int id) {
        for (final o in l) {
          if (o.id == id) return o.ad as String;
        }
        return null;
      }

      if (il > 0) {
        a['il'] = e['il']?.isNotEmpty == true
            ? e['il']!
            : (bul(await adr.iller(), il) ?? '');
      }
      if (ilce > 0) {
        a['ilce'] = e['ilce']?.isNotEmpty == true
            ? e['ilce']!
            : (bul(await adr.ilceler(il), ilce) ?? '');
      }
      if (semt > 0) {
        a['semt'] = e['semt']?.isNotEmpty == true
            ? e['semt']!
            : (bul(await adr.semtler(ilce), semt) ?? '');
      }
      if (mahalle > 0) {
        a['mahalle'] = e['mahalle']?.isNotEmpty == true
            ? e['mahalle']!
            : (bul(await adr.mahalleler(semt), mahalle) ?? '');
      }
    } catch (_) {
      for (final k in ['il', 'ilce', 'semt', 'mahalle']) {
        if ((e[k] ?? '').isNotEmpty) a[k] = e[k]!;
      }
    }
    if (mounted) setState(() => _adres = a);
  }

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TalepFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

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
    await _depo.sil(widget.yerelId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _ac(Uri uri) async {
    final tamam = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!tamam && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Bu işlem için uygun bir uygulama bulunamadı.'),
          ),
        );
    }
  }

  String _kimNe(Object? b) {
    if (b is! Map) return '—';
    final ad = '${b['adi'] ?? ''}'.trim();
    final z = uzunZaman(b['zaman'] as String?);
    final p = [if (ad.isNotEmpty) ad, ?z];
    return p.isEmpty ? '—' : p.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = _talep;
    if (!_yuklendi || t == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final durum = _durumlar[t.durum];
    final kategori = _kategoriler[t.katno];
    final icerik = htmlDuz(t.s('icerik'));
    final islem = htmlDuz(t.s('yapilan_islem'));
    final mulakat = uzunTarih(t.mulakatTarihi);
    final tel = t.telefon.trim();
    final refTel = t.s('referans_telefon').trim();
    final ek = _ek;
    final konum = [
      _adres['il'],
      _adres['ilce'],
      _adres['semt'],
      _adres['mahalle'],
    ].where((e) => (e ?? '').isNotEmpty).join(' / ');
    final smsler = [
      for (final x in (ek?['smsler'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final ustYazilar = [
      for (final x in (ek?['ust_yazilar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final gecmis = [
      for (final x in (ek?['gecmis'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final sunucuDosyalari = [
      for (final x in (ek?['dosyalar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final bekleyenYuklemeler = _dosyaIslemleri
        .where((o) => o.tur == 'dosya')
        .toList();
    final silinecekler = {
      for (final o in _dosyaIslemleri.where((o) => o.tur == 'dosya_sil'))
        '${o.govde['ad']}',
    };
    final rehber = ek?['rehber'] as Map?;
    final hatirlatici = t.i('hatirlatici') == 1
        ? 'Evet · ${uzunTarih(t.v['hatirlatici_tarih'] as String?) ?? ''}'
        : (t.i('hatirlatici') == 2 ? 'Hayır' : null);
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(
      zemin,
      tema.colorScheme.primary,
      acik ? 0.10 : 0.14,
    )!;

    final karolar = <_KaroVeri>[
      if (mulakat != null)
        _KaroVeri(Icons.event_available_outlined, 'Mülakat tarihi', mulakat),
      if (t.s('mulakat_yeri').isNotEmpty)
        _KaroVeri(
          Icons.meeting_room_outlined,
          'Mülakat yeri',
          t.s('mulakat_yeri'),
        ),
      if (t.s('ilgili_kurum').isNotEmpty)
        _KaroVeri(
          Icons.account_balance_outlined,
          'İlgili kurum',
          t.s('ilgili_kurum'),
          genis: true,
        ),
      if (t.s('tcno').isNotEmpty)
        _KaroVeri(Icons.badge_outlined, 'T.C. kimlik no', t.s('tcno')),
      if (hatirlatici != null)
        _KaroVeri(
          Icons.notifications_active_outlined,
          'Hatırlatıcı',
          hatirlatici,
        ),
      if (t.no != null) _KaroVeri(Icons.tag_rounded, 'Kayıt no', '${t.no}'),
    ];

    return Scaffold(
      floatingActionButton: KompaktDugme(
        ikon: Icons.edit_outlined,
        etiket: _sorun?.durum == 'cakisma' ? 'Çakışmayı çöz' : 'Düzenle',
        onPressed: _duzenle,
      ),
      body: Column(
        children: [
          ModulHero(
            geri: true,
            baslik: 'TALEP DETAYI',
            altBaslik: [
              if (t.adBuyuk.isNotEmpty) t.adBuyuk,
              uzunTarih(t.tarih),
            ].whereType<String>().join(' · '),
            eylemler: [
              if (_ekYukleniyor)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'sil') _sil();
                  if (v == 'duzenle') _duzenle();
                  if (v == 'yenile') _ekiYenile();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'duzenle',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Düzenle'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'yenile',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh_rounded),
                      title: Text('Ayrıntıları yenile'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sil',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Sil'),
                    ),
                  ),
                ],
              ),
            ],
            alt: (rehber?['kara_liste'] == true || t.bekleyen)
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (rehber?['kara_liste'] == true)
                          const _Rozet(
                            metin: 'Kara liste',
                            ikon: Icons.block_rounded,
                          ),
                        if (rehber?['kara_liste'] == true && t.bekleyen)
                          const SizedBox(width: 8),
                        if (t.bekleyen)
                          const _Rozet(
                            metin: 'Gönderilecek',
                            ikon: Icons.cloud_upload_outlined,
                          ),
                      ],
                    ),
                  )
                : null,
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.3, 1],
                ),
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 110),
                children: [
                  _Sutun(
                    cocuklar: [
                      if (_sorun != null) _SorunSeridi(op: _sorun!),
                      if (ek == null && t.no != null && !_ekYukleniyor)
                        _Bilgi(
                          ikon: Icons.cloud_off_rounded,
                          metin: _ekHata
                              ? 'Kaydeden, SMS, dosya ve geçmiş bilgileri için bağlantı gerekir. Bağlantı gelince yenileyin.'
                              : 'Kaydeden, SMS, dosya ve geçmiş bilgileri yükleniyor…',
                          eylem: _ekHata
                              ? TextButton(
                                  onPressed: _ekiYenile,
                                  child: const Text('Yenile'),
                                )
                              : null,
                        ),
                      _Ozet(
                        ad: t.adBuyuk.isEmpty ? '(ADSIZ)' : t.adBuyuk,
                        durum: durum?.adi ?? (ek?['durum_adi'] as String?),
                        renk: talepRengi(durum?.renk),
                        kategori: kategori ?? (ek?['kategori_adi'] as String?),
                        tarih: uzunTarih(t.tarih),
                        goreli: goreliGun(t.tarih),
                      ),
                      _Kart(
                        baslik: 'Talep',
                        ikon: Icons.notes_rounded,
                        cocuk: icerik.isEmpty
                            ? const _Bos('İçerik girilmemiş')
                            : _Alinti(icerik),
                      ),
                      if (islem.isNotEmpty)
                        _Kart(
                          baslik: 'Yapılan işlem',
                          ikon: Icons.task_alt_outlined,
                          cocuk: _Alinti(islem, yesil: true),
                        ),
                      if (tel.isNotEmpty || t.s('referans').isNotEmpty)
                        _Kart(
                          baslik: 'İletişim',
                          ikon: Icons.contact_phone_outlined,
                          cocuk: Column(
                            children: [
                              if (tel.isNotEmpty)
                                _IletisimSatiri(
                                  ad: t.adBuyuk,
                                  tel: tel,
                                  ara: () => _ac(Uri(scheme: 'tel', path: tel)),
                                  mesaj: () => _ac(
                                    Uri.parse(
                                      'https://wa.me/${telefonRakamlari(tel)}',
                                    ),
                                  ),
                                  sms: () => _ac(Uri(scheme: 'sms', path: tel)),
                                ),
                              if (t.s('referans').isNotEmpty ||
                                  refTel.isNotEmpty) ...[
                                if (tel.isNotEmpty) const _Ayirac(),
                                _IletisimSatiri(
                                  ad: t.s('referans').isEmpty
                                      ? 'Referans'
                                      : '${t.s('referans')} (referans)',
                                  tel: refTel,
                                  ara: refTel.isEmpty
                                      ? null
                                      : () => _ac(
                                          Uri(scheme: 'tel', path: refTel),
                                        ),
                                  mesaj: refTel.isEmpty
                                      ? null
                                      : () => _ac(
                                          Uri.parse(
                                            'https://wa.me/${telefonRakamlari(refTel)}',
                                          ),
                                        ),
                                  sms: refTel.isEmpty
                                      ? null
                                      : () => _ac(
                                          Uri(scheme: 'sms', path: refTel),
                                        ),
                                ),
                              ],
                              if (rehber != null) ...[
                                const _Ayirac(),
                                _SatirAlan(
                                  Icons.contacts_outlined,
                                  'Telefon rehberi',
                                  rehber['var'] == true
                                      ? (rehber['kara_liste'] == true
                                            ? 'Kayıtlı · kara listede'
                                            : 'Kayıtlı')
                                      : 'Kayıtlı değil',
                                ),
                              ],
                            ],
                          ),
                        ),
                      _Kart(
                        baslik: 'Ek dosyalar',
                        ikon: Icons.attach_file_rounded,
                        sayi:
                            sunucuDosyalari.length + bekleyenYuklemeler.length,
                        cocuk:
                            (sunucuDosyalari.isEmpty &&
                                bekleyenYuklemeler.isEmpty)
                            ? _Bos(
                                ek == null
                                    ? 'Bağlantı kurulunca yüklenir'
                                    : 'Ek dosya yok',
                              )
                            : Column(
                                children: [
                                  for (final d in sunucuDosyalari)
                                    DosyaSatiri(
                                      ad: '${d['goruntu']}',
                                      boyut: d['boyut'] as int?,
                                      etiket: silinecekler.contains(d['ad'])
                                          ? 'silinecek'
                                          : null,
                                      tikla: t.no == null
                                          ? null
                                          : () => sunucuDosyasiniAc(
                                              context,
                                              widget.veri.motor.api,
                                              t.no!,
                                              '${d['ad']}',
                                              '${d['goruntu']}',
                                            ),
                                    ),
                                  for (final o in bekleyenYuklemeler)
                                    DosyaSatiri(
                                      ad: '${o.govde['ad']}',
                                      boyut: (o.govde['boyut'] as num?)
                                          ?.toInt(),
                                      etiket: 'gönderilecek',
                                    ),
                                ],
                              ),
                      ),
                      if (konum.isNotEmpty)
                        _Kart(
                          baslik: 'İkamet bilgisi',
                          ikon: Icons.location_on_outlined,
                          cocuk: Text(
                            konum,
                            style: tema.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      _Kart(
                        baslik: 'SMS bilgisi',
                        ikon: Icons.sms_outlined,
                        sayi: smsler.length,
                        cocuk: ek == null
                            ? const _Bos('Bağlantı kurulunca yüklenir')
                            : (smsler.isEmpty
                                  ? const _Bos(
                                      'Bu talep için SMS gönderilmemiş',
                                    )
                                  : Column(
                                      children: [
                                        for (final s in smsler)
                                          _SmsSatiri(sms: s),
                                      ],
                                    )),
                      ),
                      if (ek != null && ustYazilar.isNotEmpty)
                        _Kart(
                          baslik: 'Üst yazı bilgisi',
                          ikon: Icons.mail_outline,
                          sayi: ustYazilar.length,
                          cocuk: Column(
                            children: [
                              for (final y in ustYazilar)
                                _SatirAlan(
                                  Icons.description_outlined,
                                  uzunTarih('${y['tarih']}'.split(' ').first) ??
                                      '',
                                  '${y['kisi']} (${y['unvan']})',
                                ),
                            ],
                          ),
                        ),
                      if (karolar.isNotEmpty)
                        _Kart(
                          baslik: 'Ayrıntılar',
                          ikon: Icons.info_outline_rounded,
                          cocuk: _KaroIzgara(karolar),
                        ),
                      _Kart(
                        baslik: 'Kayıt bilgileri',
                        ikon: Icons.history_toggle_off_rounded,
                        cocuk: ek == null
                            ? const _Bos('Bağlantı kurulunca yüklenir')
                            : Column(
                                children: [
                                  _SatirAlan(
                                    Icons.person_outline_rounded,
                                    'Kaydeden',
                                    (ek['ekleyen'] as String?)?.isNotEmpty ==
                                            true
                                        ? ek['ekleyen'] as String
                                        : '—',
                                  ),
                                  const _Ayirac(),
                                  _SatirAlan(
                                    Icons.add_circle_outline_rounded,
                                    'İlk kayıt',
                                    _kimNe(ek['ilk_kayit']),
                                  ),
                                  const _Ayirac(),
                                  _SatirAlan(
                                    Icons.update_rounded,
                                    'Son güncelleme',
                                    ek['son_guncelleme'] == null
                                        ? 'Henüz güncellenmedi'
                                        : _kimNe(ek['son_guncelleme']),
                                  ),
                                ],
                              ),
                      ),
                      if (gecmis.isNotEmpty)
                        _Kart(
                          baslik: 'Değişiklik geçmişi',
                          ikon: Icons.history_rounded,
                          sayi: gecmis.length,
                          cocuk: Column(
                            children: [
                              for (var i = 0; i < gecmis.length; i++)
                                _ZamanCizgisi(
                                  son: i == gecmis.length - 1,
                                  baslik: [
                                    uzunZaman(gecmis[i]['tarih'] as String?),
                                    if ('${gecmis[i]['kim']}'.isNotEmpty)
                                      '${gecmis[i]['kim']}',
                                  ].whereType<String>().join(' · '),
                                  altMetin:
                                      ((gecmis[i]['degisen'] as List?) ??
                                              const [])
                                          .isEmpty
                                      ? 'Değişiklik yok (kayıt yeniden kaydedildi)'
                                      : 'Değişen: ${((gecmis[i]['degisen'] as List).join(', '))}',
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<BoxShadow> _golge(BuildContext context) {
  final acik = Theme.of(context).brightness == Brightness.light;
  return [
    BoxShadow(
      color: (acik ? Marka.lacivert : Colors.black).withValues(
        alpha: acik ? 0.08 : 0.35,
      ),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

/// İçeriği tablette de okunaklı kalacak genişlikte ortalar; çocuklar arası boşluk bırakır.
class _Sutun extends StatelessWidget {
  const _Sutun({required this.cocuklar});

  final List<Widget> cocuklar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: cocuklar),
        ),
      ),
    );
  }
}

/// Premium bölüm kartı: yumuşak gölge, ikon rozeti, kalın başlık ve isteğe bağlı adet.
class _Kart extends StatelessWidget {
  const _Kart({
    required this.baslik,
    required this.ikon,
    required this.cocuk,
    this.sayi,
  });

  final String baslik;
  final IconData ikon;
  final Widget cocuk;
  final int? sayi;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vurgu = tema.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: _golge(context),
        ),
        child: Material(
          color: tema.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: vurgu.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(ikon, size: 19, color: vurgu),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        trBuyuk(baslik),
                        style: tema.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (sayi != null && sayi! > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: vurgu.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$sayi',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: vurgu,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                cocuk,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Üstteki özet kartı: durum renginde şerit, büyük durum etiketi, kategori ve tarih.
class _Ozet extends StatelessWidget {
  const _Ozet({
    required this.ad,
    required this.durum,
    required this.renk,
    required this.kategori,
    required this.tarih,
    required this.goreli,
  });

  final String ad;
  final String? durum;
  final Color? renk;
  final String? kategori;
  final String? tarih;
  final String goreli;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final r = renk ?? tema.colorScheme.outline;
    final koyu = acik
        ? Color.lerp(r, Colors.black, 0.38)!
        : Color.lerp(r, Colors.white, 0.45)!;

    Widget etiket(IconData ikon, String metin) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tema.colorScheme.onSurface.withValues(alpha: acik ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 15, color: tema.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              metin,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tema.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: _golge(context),
        ),
        child: Material(
          color: tema.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [r, r.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      r.withValues(alpha: acik ? 0.10 : 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad,
                      style: tema.textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: r.withValues(alpha: acik ? 0.16 : 0.30),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: r.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: r,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                durum ?? 'Durum yok',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: koyu,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (goreli.isNotEmpty)
                          Text(
                            goreli,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: tema.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (kategori != null && kategori!.isNotEmpty)
                          etiket(Icons.category_outlined, kategori!),
                        if (tarih != null)
                          etiket(Icons.calendar_today_outlined, tarih!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ayirac extends StatelessWidget {
  const _Ayirac();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant
          .withValues(alpha: 0.6),
    ),
  );
}

/// Metni sol çizgili, yumuşak zeminli bir alıntı kutusunda gösterir (talep metni, yapılan işlem).
class _Alinti extends StatelessWidget {
  const _Alinti(this.metin, {this.yesil = false});

  final String metin;
  final bool yesil;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final renk = yesil ? const Color(0xFF12A150) : tema.colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: renk, width: 3.5)),
      ),
      child: SelectableText(
        metin,
        style: tema.textTheme.bodyLarge?.copyWith(height: 1.5, fontSize: 15.5),
      ),
    );
  }
}

class _KaroVeri {
  const _KaroVeri(this.ikon, this.etiket, this.deger, {this.genis = false});

  final IconData ikon;
  final String etiket;
  final String deger;
  final bool genis;
}

/// İkonlu bilgi kutucukları: iki sütun; uzun değerler ("genis") tam satır kaplar.
class _KaroIzgara extends StatelessWidget {
  const _KaroIzgara(this.karolar);

  final List<_KaroVeri> karolar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final yarim = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final k in karolar)
              SizedBox(width: k.genis ? c.maxWidth : yarim, child: _Karo(k)),
          ],
        );
      },
    );
  }
}

class _Karo extends StatelessWidget {
  const _Karo(this.k);

  final _KaroVeri k;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tema.colorScheme.onSurface.withValues(
          alpha: acik ? 0.045 : 0.09,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(k.ikon, size: 20, color: tema.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  k.etiket,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  k.deger,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// İkonlu "etiket → değer" satırı (kayıt bilgileri, rehber durumu).
class _SatirAlan extends StatelessWidget {
  const _SatirAlan(this.ikon, this.etiket, this.deger);

  final IconData ikon;
  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ikon, size: 19, color: tema.colorScheme.onSurfaceVariant),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiket,
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                deger,
                style: tema.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmsSatiri extends StatelessWidget {
  const _SmsSatiri({required this.sms});

  final Map<String, dynamic> sms;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ok = sms['basarili'] == true;
    final renk = ok ? const Color(0xFF12A150) : tema.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: renk.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              ok ? Icons.check_rounded : Icons.error_outline_rounded,
              size: 17,
              color: renk,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sms['telefon']}',
                  style: tema.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    uzunZaman(sms['tarih'] as String?),
                    '${sms['tur'] ?? ''}',
                  ].where((e) => (e ?? '').isNotEmpty).join(' · '),
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Değişiklik geçmişi için dikey çizgili zaman çizelgesi satırı.
class _ZamanCizgisi extends StatelessWidget {
  const _ZamanCizgisi({
    required this.baslik,
    required this.altMetin,
    required this.son,
  });

  final String baslik;
  final String altMetin;
  final bool son;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vurgu = tema.colorScheme.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: tema.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: vurgu, width: 3),
                  ),
                ),
                if (!son)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: vurgu.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: son ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baslik,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    altMetin,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bos extends StatelessWidget {
  const _Bos(this.metin);

  final String metin;

  @override
  Widget build(BuildContext context) => Text(
    metin,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    ),
  );
}

class _Bilgi extends StatelessWidget {
  const _Bilgi({required this.ikon, required this.metin, this.eylem});

  final IconData ikon;
  final String metin;
  final Widget? eylem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tema.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(ikon),
            const SizedBox(width: 12),
            Expanded(child: Text(metin, style: tema.textTheme.bodyMedium)),
            ?eylem,
          ],
        ),
      ),
    );
  }
}

/// Kişi satırı: baş harf avatarı, ad ve numara; sağda arama, WhatsApp ve SMS düğmeleri.
class _IletisimSatiri extends StatelessWidget {
  const _IletisimSatiri({
    required this.ad,
    required this.tel,
    required this.ara,
    required this.mesaj,
    required this.sms,
  });

  final String ad;
  final String tel;
  final VoidCallback? ara;
  final VoidCallback? mesaj;
  final VoidCallback? sms;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tel.isEmpty ? '—' : tel,
                style: tema.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        _Daire(ikon: Icons.call_rounded, ipucu: 'Ara', tikla: ara),
        const SizedBox(width: 8),
        _Daire(
          ikon: Icons.chat_rounded,
          ipucu: 'WhatsApp',
          tikla: mesaj,
          yesil: true,
        ),
        const SizedBox(width: 8),
        _Daire(ikon: Icons.sms_rounded, ipucu: 'SMS', tikla: sms, mor: true),
      ],
    );
  }
}

class _Daire extends StatelessWidget {
  const _Daire({
    required this.ikon,
    required this.ipucu,
    required this.tikla,
    this.yesil = false,
    this.mor = false,
  });

  final IconData ikon;
  final String ipucu;
  final VoidCallback? tikla;
  final bool yesil;
  final bool mor;

  @override
  Widget build(BuildContext context) {
    final renk = yesil
        ? const Color(0xFF12A150)
        : mor
        ? const Color(0xFFE08A00)
        : Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: ipucu,
      child: Material(
        color: renk.withValues(alpha: tikla == null ? 0.06 : 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: tikla,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              ikon,
              color: tikla == null ? renk.withValues(alpha: 0.4) : renk,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

class _Rozet extends StatelessWidget {
  const _Rozet({required this.metin, required this.ikon});

  final String metin;
  final IconData ikon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikon, size: 14, color: const Color(0xFFC3CFDE)),
        const SizedBox(width: 6),
        Text(
          metin,
          style: const TextStyle(color: Color(0xFFE3EAF3), fontSize: 12.5),
        ),
      ],
    ),
  );
}

class _SorunSeridi extends StatelessWidget {
  const _SorunSeridi({required this.op});

  final KuyrukOp op;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cakisma = op.durum == 'cakisma';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cakisma
              ? tema.colorScheme.tertiaryContainer
              : tema.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              cakisma ? Icons.warning_amber_rounded : Icons.error_outline,
              color: cakisma ? Colors.amber.shade900 : tema.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cakisma
                    ? 'Bu talep siz çevrimdışıyken başka biri tarafından değiştirilmiş. Hangisini tutacağınızı seçmek için "Çakışmayı çöz"e basın.'
                    : 'Son değişiklik gönderilemedi: ${op.mesaj}',
                style: tema.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
