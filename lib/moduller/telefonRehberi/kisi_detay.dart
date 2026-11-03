import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/rehber.dart';
import '../../veri/rehber_deposu.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_ortak.dart';
import 'cihaz_rehberi.dart';
import 'gorusme_detay.dart';
import 'gorusme_formu.dart';
import 'kisi_formu.dart';
import 'rehber_ortak.dart';

/// Kişi ayrıntısı: hızlı eylemler (ara, WhatsApp, SMS, e-posta, telefona kaydet), tüm telefonlar, adres, doğum günü, not,
/// görüşme / talep / randevu sayıları ve son görüşmeler, kayıt bilgileri.
class KisiDetay extends StatefulWidget {
  const KisiDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<KisiDetay> createState() => _KisiDetayState();
}

class _KisiDetayState extends State<KisiDetay> {
  Kisi? _k;
  KuyrukOp? _sorun;
  Map<String, dynamic>? _ek;
  RehberReferans _ref = RehberReferans({});
  List<Gorusme> _gorusmeler = [];
  ({int gorusme, int talep, int randevu}) _sayilar = (
    gorusme: 0,
    talep: 0,
    randevu: 0,
  );
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _ekHata = false;

  RehberDeposu get _depo => widget.veri.rehber;

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
    final k = await _depo.kisiGetir(widget.yerelId);
    final s = (await _depo.sorunlular(RehberVarlik.kisi))[widget.yerelId];
    final ref = await _depo.referans();
    if (!mounted) return;
    if (k == null || k.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ek = k.no == null ? null : await _depo.ekOku('kisi${k.no}');
    final g = await _depo.kisiGorusmeleri(k);
    final say = await _depo.kisiSayilari(k);
    if (!mounted) return;
    final ilk = !_yuklendi;
    setState(() {
      _k = k;
      _sorun = s;
      _ek = ek;
      _ref = RehberReferans(ref);
      _gorusmeler = g;
      _sayilar = say;
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _k?.no;
    final senk = widget.veri.motor.rehberSenkron;
    if (no == null || senk == null) return;
    setState(() {
      _ekYukleniyor = true;
      _ekHata = false;
    });
    try {
      final v = await senk.kisiAyrintisi(no);
      if (mounted) setState(() => _ek = v);
    } on ApiHata {
      if (mounted) setState(() => _ekHata = true);
    } finally {
      if (mounted) setState(() => _ekYukleniyor = false);
    }
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => KisiFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _gorusmeEkle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GorusmeFormu(veri: widget.veri, kisi: _k),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kişi silinsin mi?'),
        content: const Text(
          'Kayıt çöp kutusuna taşınır (web panelinden geri alınabilir). Görüşme kayıtları silinmez.',
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
    await _depo.kisiSil(widget.yerelId);
    if (mounted) Navigator.of(context).pop();
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
    final k = _k;
    if (!_yuklendi || k == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final kat = _ref.kategoriAdi(k.katno);
    final dogum = k.sonrakiDogumGunu();
    final iletisimVar =
        k.cep1.isNotEmpty ||
        k.cep2.isNotEmpty ||
        k.is1.isNotEmpty ||
        k.is2.isNotEmpty ||
        k.faks.isNotEmpty ||
        k.email.isNotEmpty ||
        k.adres.isNotEmpty;

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
            ikon: Icons.contacts_outlined,
            baslik: 'KİŞİ DETAYI',
            altBaslik: kat.isEmpty ? 'Rehber' : kat,
            eylemler: [
              if (_ekYukleniyor)
                const Padding(
                  padding: EdgeInsets.all(10),
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
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.more_vert),
                onSelected: (v) async {
                  switch (v) {
                    case 'duzenle':
                      _duzenle();
                    case 'gorusme':
                      _gorusmeEkle();
                    case 'kara':
                      await _depo.karaDegistir(widget.yerelId, !k.kara);
                    case 'cihaz':
                      await cihazRehberineKaydet(context, k);
                    case 'yenile':
                      _ekiYenile();
                    case 'sil':
                      _sil();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'duzenle',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Düzenle'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'gorusme',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.phone_in_talk_outlined),
                      title: Text('Görüşme ekle'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'kara',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        k.kara ? Icons.shield_outlined : Icons.block_rounded,
                      ),
                      title: Text(
                        k.kara ? 'Kara listeden çıkar' : 'Kara listeye al',
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'cihaz',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_add_alt_1_outlined),
                      title: Text('Telefon rehberine kaydet'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'yenile',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.refresh_rounded),
                      title: Text('Ayrıntıları yenile'),
                    ),
                  ),
                  const PopupMenuItem(
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_sorun != null)
                            _SorunSeridi(
                              op: _sorun!,
                              depo: _depo,
                              motor: widget.veri.motor,
                            ),
                          ProgramKutu(
                            baslik: 'Kişi / kurum',
                            ikon: Icons.person_outline_rounded,
                            sag: k.kara
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE11D48)
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'KARA LİSTE',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFBE123C),
                                      ),
                                    ),
                                  )
                                : null,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trBuyuk(k.adi),
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                if (k.unvan.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      k.unvan.trim(),
                                      style: tema.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _Eylem(
                                      ikon: Icons.call_rounded,
                                      ad: 'Ara',
                                      renk: const Color(0xFF16A34A),
                                      tikla: k.anaTelefon.isEmpty
                                          ? null
                                          : () => telefonAra(k.anaTelefon),
                                    ),
                                    _Eylem(
                                      ikon: Icons.chat_rounded,
                                      ad: 'WhatsApp',
                                      renk: const Color(0xFF0E9F6E),
                                      tikla: k.anaTelefon.isEmpty
                                          ? null
                                          : () => whatsappAc(k.anaTelefon),
                                    ),
                                    _Eylem(
                                      ikon: Icons.sms_outlined,
                                      ad: 'SMS',
                                      renk: cs.primary,
                                      tikla: k.anaTelefon.isEmpty
                                          ? null
                                          : () => smsAc(k.anaTelefon),
                                    ),
                                    _Eylem(
                                      ikon: Icons.mail_outline_rounded,
                                      ad: 'E-posta',
                                      renk: const Color(0xFFD97706),
                                      tikla: k.email.isEmpty
                                          ? null
                                          : () => epostaAc(k.email),
                                    ),
                                    _Eylem(
                                      ikon: Icons.person_add_alt_1_outlined,
                                      ad: 'Kaydet',
                                      renk: const Color(0xFF7C3AED),
                                      tikla: () =>
                                          cihazRehberineKaydet(context, k),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (iletisimVar)
                            ProgramKutu(
                              baslik: 'İletişim',
                              ikon: Icons.phone_outlined,
                              cocuk: Column(
                                children: [
                                  TelefonSatiri(
                                    etiket: 'Cep telefonu',
                                    numara: k.cep1,
                                    ikon: Icons.phone_android_outlined,
                                    mesajlasma: true,
                                  ),
                                  TelefonSatiri(
                                    etiket: 'Cep telefonu 2',
                                    numara: k.cep2,
                                    ikon: Icons.phone_android_outlined,
                                    mesajlasma: true,
                                  ),
                                  TelefonSatiri(
                                    etiket: 'İş telefonu',
                                    numara: k.is1,
                                    dahili: k.isd1,
                                    ikon: Icons.business_outlined,
                                  ),
                                  TelefonSatiri(
                                    etiket: 'İş telefonu 2',
                                    numara: k.is2,
                                    dahili: k.isd2,
                                    ikon: Icons.business_outlined,
                                  ),
                                  TelefonSatiri(
                                    etiket: 'Faks',
                                    numara: k.faks,
                                    ikon: Icons.print_outlined,
                                  ),
                                  if (k.email.isNotEmpty)
                                    _Satir(
                                      ikon: Icons.alternate_email,
                                      etiket: 'E-posta',
                                      deger: k.email,
                                      tikla: () => epostaAc(k.email),
                                    ),
                                  if (k.adres.isNotEmpty)
                                    _Satir(
                                      ikon: Icons.place_outlined,
                                      etiket: 'Adres',
                                      deger: k.adres,
                                      sag: Icons.map_outlined,
                                      tikla: () async {
                                        if (!await haritadaAc(k.adres)) {
                                          _mesaj('Harita açılamadı.');
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                          if (dogum != null)
                            ProgramKutu(
                              baslik: 'Doğum günü',
                              ikon: Icons.cake_outlined,
                              cocuk: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${k.dogum!.day} ${trAylar[k.dogum!.month]}${k.dogum!.year > 1900 ? ' ${k.dogum!.year}' : ''}',
                                      style: tema.textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    dogum.kalan == 0
                                        ? 'Bugün!${dogum.yas != null ? ' (${dogum.yas} yaş)' : ''}'
                                        : '${dogum.kalan} gün kaldı${dogum.yas != null ? ' · ${dogum.yas}. yaş' : ''}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: dogum.kalan <= 7
                                          ? const Color(0xFFD97706)
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (k.notu.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Bilgi notu',
                              ikon: Icons.notes_rounded,
                              cocuk: SelectableText(
                                k.notu.trim(),
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ProgramKutu(
                            baslik: 'Etkileşimler',
                            ikon: Icons.history_rounded,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _Sayac(
                                      sayi: _sayilar.gorusme,
                                      etiket: 'Görüşme',
                                      renk: cs.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    _Sayac(
                                      sayi: _sayilar.talep,
                                      etiket: 'Talep',
                                      renk: const Color(0xFF0E9F6E),
                                    ),
                                    const SizedBox(width: 8),
                                    _Sayac(
                                      sayi: _sayilar.randevu,
                                      etiket: 'Randevu',
                                      renk: const Color(0xFFD97706),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                for (final g in _gorusmeler)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => GorusmeDetay(
                                          veri: widget.veri,
                                          yerelId: g.yerelId!,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            gorusmeDurumIkonu(g.d1),
                                            size: 18,
                                            color: gorusmeDurumRengi(g.d1),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              g.konu.trim().isEmpty
                                                  ? _ref.durumAdi(g.d1)
                                                  : g.konu.trim(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '${g.t1.day} ${trAylarKisa[g.t1.month]} ${g.t1.year}',
                                            style: tema.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _gorusmeEkle,
                                    icon: const Icon(Icons.add_call, size: 18),
                                    label: const Text('Görüşme ekle'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Kayıt bilgileri',
                            ikon: Icons.info_outline_rounded,
                            cocuk: _ek == null
                                ? Text(
                                    _ekHata
                                        ? 'Kayıt zamanları için bağlantı gerekir.'
                                        : 'Yükleniyor…',
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  )
                                : Column(
                                    children: [
                                      _Satir2(
                                        'İlk kayıt',
                                        _kimNe(_ek!['ilk_kayit']),
                                      ),
                                      _Satir2(
                                        'Son güncelleme',
                                        _kimNe(_ek!['son_guncelleme']),
                                      ),
                                    ],
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
        ],
      ),
    );
  }
}

class _Eylem extends StatelessWidget {
  const _Eylem({
    required this.ikon,
    required this.ad,
    required this.renk,
    required this.tikla,
  });

  final IconData ikon;
  final String ad;
  final Color renk;
  final VoidCallback? tikla;

  @override
  Widget build(BuildContext context) {
    final etkin = tikla != null;
    final c = etkin ? renk : Theme.of(context).colorScheme.outline;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: tikla,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(ikon, color: c, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              ad,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sayac extends StatelessWidget {
  const _Sayac({required this.sayi, required this.etiket, required this.renk});

  final int sayi;
  final String etiket;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final koyuluk = Theme.of(context).brightness == Brightness.light
        ? Colors.black
        : Colors.white;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: renk.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$sayi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color.lerp(renk, koyuluk, 0.3),
              ),
            ),
            Text(etiket, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir({
    required this.ikon,
    required this.etiket,
    required this.deger,
    this.tikla,
    this.sag,
  });

  final IconData ikon;
  final String etiket;
  final String deger;
  final VoidCallback? tikla;
  final IconData? sag;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: tikla,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiket,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    deger,
                    style: tema.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (sag != null) Icon(sag, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _Satir2 extends StatelessWidget {
  const _Satir2(this.etiket, this.deger);

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              etiket,
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              deger.isEmpty ? '—' : deger,
              style: tema.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SorunSeridi extends StatelessWidget {
  const _SorunSeridi({
    required this.op,
    required this.depo,
    required this.motor,
  });

  final KuyrukOp op;
  final RehberDeposu depo;
  final dynamic motor;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  cakisma ? Icons.warning_amber_rounded : Icons.error_outline,
                  color: cakisma
                      ? Colors.amber.shade900
                      : tema.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cakisma
                        ? 'Bu kayıt siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
                        : 'Son değişiklik gönderilemedi: ${op.mesaj}',
                    style: tema.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (cakisma) ...[
                  FilledButton.tonal(
                    onPressed: () async {
                      await depo.cakismaBenimkiniGonder(RehberVarlik.kisi, op);
                      motor.senkronla();
                    },
                    child: const Text('Benimkini koru'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        depo.cakismaSunucuyuAl(RehberVarlik.kisi, op),
                    child: const Text('Sunucudakini al'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () => depo.islemiIptalEt(RehberVarlik.kisi, op),
                    child: const Text('Değişikliği geri al'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
