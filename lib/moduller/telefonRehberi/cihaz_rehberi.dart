import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../veri/yazi_formatlari.dart';
import '../../veri/rehber.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/modul_hero.dart';
import 'rehber_ortak.dart';

/// Kişiyi telefonun kendi rehberine kaydeder (izin istenir). Başarılıysa true.
Future<bool> cihazRehberineKaydet(BuildContext context, Kisi k) async {
  final mesaj = ScaffoldMessenger.of(context);
  void bildir(String m) => mesaj
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
  try {
    final izin = await FlutterContacts.permissions.request(
      PermissionType.readWrite,
    );
    if (izin != PermissionStatus.granted && izin != PermissionStatus.limited) {
      bildir('Telefon rehberine yazma izni verilmedi.');
      return false;
    }
    final parcalar = k.adi.trim().split(RegExp(r'\s+'));
    final ad = parcalar.length > 1
        ? parcalar.sublist(0, parcalar.length - 1).join(' ')
        : parcalar.first;
    final soyad = parcalar.length > 1 ? parcalar.last : '';
    final telefonlar = [
      for (final t in [k.cep1, k.cep2])
        if (t.trim().isNotEmpty) Phone(number: t.trim()),
      for (final t in [k.is1, k.is2])
        if (t.trim().isNotEmpty)
          Phone(number: t.trim(), label: const Label(PhoneLabel.work)),
    ];
    final d = k.dogum;
    await FlutterContacts.create(
      Contact(
        name: Name(first: ad, last: soyad),
        phones: telefonlar,
        emails: [if (k.email.trim().isNotEmpty) Email(address: k.email.trim())],
        organizations: [
          if (k.unvan.trim().isNotEmpty) Organization(jobTitle: k.unvan.trim()),
        ],
        addresses: [
          if (k.adres.trim().isNotEmpty) Address(formatted: k.adres.trim()),
        ],
        events: [
          if (d != null)
            Event(
              year: d.year,
              month: d.month,
              day: d.day,
              label: const Label(EventLabel.birthday),
            ),
        ],
        notes: [if (k.notu.trim().isNotEmpty) Note(note: k.notu.trim())],
      ),
    );
    bildir('Telefon rehberine kaydedildi.');
    return true;
  } catch (e) {
    bildir('Telefon rehberine kaydedilemedi.');
    return false;
  }
}

class _Aday {
  _Aday(this.id, this.adi, this.telefonlar, this.email, this.unvan);

  final String id;
  final String adi;
  final List<String> telefonlar;
  final String email;
  final String unvan;
  bool var_ = false;
}

/// Telefonun rehberinden uygulamanın rehberine toplu aktarım: kişiler listelenir, seçilenler seçilen kategoriyle eklenir.
/// Zaten kayıtlı olanlar (ad + cep telefonu) işaretlenir ve varsayılan olarak seçilmez.
class CihazRehberi extends StatefulWidget {
  const CihazRehberi({super.key, required this.veri});

  final VeriKatmani veri;

  @override
  State<CihazRehberi> createState() => _CihazRehberiState();
}

class _CihazRehberiState extends State<CihazRehberi> {
  List<_Aday> _liste = [];
  final _secili = <String>{};
  RehberReferans _ref = RehberReferans({});
  int _kat = 0;
  bool _yukleniyor = true;
  bool _izinYok = false;
  bool _aktariliyor = false;
  final _ara = TextEditingController();
  String _kelime = '';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _ara.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _izinYok = false;
    });
    final ref = RehberReferans(await widget.veri.rehber.referans());
    try {
      final izin = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (izin != PermissionStatus.granted &&
          izin != PermissionStatus.limited) {
        if (mounted) {
          setState(() {
            _ref = ref;
            _izinYok = true;
            _yukleniyor = false;
          });
        }
        return;
      }
      final kisiler = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
          ContactProperty.organization,
        },
      );
      final adaylar = <_Aday>[];
      for (final c in kisiler) {
        final ad = (c.displayName ?? '').trim();
        final tel = [for (final p in c.phones) p.number.trim()]
            .where((x) => x.isNotEmpty)
            .toList();
        if (ad.isEmpty && tel.isEmpty) continue;
        adaylar.add(
          _Aday(
            c.id ?? '${adaylar.length}',
            ad.isEmpty ? tel.first : ad,
            tel,
            c.emails.isEmpty ? '' : c.emails.first.address.trim(),
            c.organizations.isEmpty
                ? ''
                : (c.organizations.first.jobTitle ??
                          c.organizations.first.name ??
                          '')
                      .trim(),
          ),
        );
      }
      adaylar.sort(
        (a, b) => siraAnahtari(a.adi).compareTo(siraAnahtari(b.adi)),
      );
      for (final a in adaylar) {
        final var_ = await widget.veri.rehber.kisiBul(
          a.adi,
          a.telefonlar.isEmpty ? '' : a.telefonlar.first,
        );
        a.var_ =
            var_ != null &&
            (a.telefonlar.isEmpty ||
                a.telefonlar.first.replaceAll(RegExp(r'\D'), '') ==
                    var_.cep1.replaceAll(RegExp(r'\D'), ''));
      }
      if (!mounted) return;
      setState(() {
        _ref = ref;
        _liste = adaylar;
        _kat = 0;
        _yukleniyor = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  List<_Aday> get _gorunen {
    final k = aramaMetni(_kelime);
    if (k.isEmpty) return _liste;
    return [
      for (final a in _liste)
        if (aramaMetni('${a.adi} ${a.telefonlar.join(' ')}').contains(k)) a,
    ];
  }

  Future<void> _aktar() async {
    if (_kat == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Eklenecek kategoriyi seçin (kategori yoksa Rehber ▸ ⋮ ▸ Kategoriler’den ekleyin).',
          ),
        ),
      );
      return;
    }
    setState(() => _aktariliyor = true);
    var n = 0;
    for (final a in _liste) {
      if (!_secili.contains(a.id)) continue;
      await widget.veri.rehber.kisiKaydet({
        'katno': _kat,
        'adi': a.adi,
        'unvan': a.unvan,
        'cep1': a.telefonlar.isNotEmpty ? a.telefonlar[0] : '',
        'cep2': a.telefonlar.length > 1 ? a.telefonlar[1] : '',
        'email': a.email.toLowerCase(),
      });
      n++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$n kişi rehbere eklendi; bağlantı varken sunucuya gönderilecek.',
          ),
        ),
      );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final gorunen = _gorunen;
    final yeniler = _liste.where((a) => !a.var_).map((a) => a.id).toSet();
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.download_for_offline_outlined,
            baslik: 'REHBERDEN AKTAR',
            altBaslik: _yukleniyor
                ? 'Telefon rehberi okunuyor…'
                : '${_liste.length} kişi · ${_secili.length} seçili',
            alt: _liste.isEmpty
                ? null
                : HeroArama(
                    controller: _ara,
                    ipucu: 'Telefon rehberinde ara',
                    degisti: (v) => setState(() => _kelime = v),
                  ),
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
              child: _yukleniyor
                  ? const Center(child: CircularProgressIndicator())
                  : _izinYok
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 44,
                              color: cs.primary,
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Telefon rehberine erişim izni verilmedi.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: _yukle,
                              child: const Text('Tekrar dene'),
                            ),
                            TextButton(
                              onPressed:
                                  FlutterContacts.permissions.openSettings,
                              child: const Text('Ayarları aç'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue:
                                      _ref.kategoriler.any(
                                        (x) => x['no'] == _kat,
                                      )
                                      ? _kat
                                      : null,
                                  isExpanded: true,
                                  hint: const Text('Seçiniz'),
                                  decoration: const InputDecoration(
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.always,
                                    labelText: 'Eklenecek kategori',
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final k in _ref.kategoriler)
                                      DropdownMenuItem(
                                        value: k['no'] as int,
                                        child: Text('${k['adi']}'),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _kat = v ?? _kat),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => setState(() {
                                  if (_secili.length >= yeniler.length) {
                                    _secili.clear();
                                  } else {
                                    _secili
                                      ..clear()
                                      ..addAll(yeniler);
                                  }
                                }),
                                child: Text(
                                  _secili.length >= yeniler.length &&
                                          yeniler.isNotEmpty
                                      ? 'Temizle'
                                      : 'Yenileri seç',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_liste.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  'Telefon rehberinizde aktarılacak kişi bulunamadı.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: gorunen.length,
                            itemBuilder: (c, i) {
                              final a = gorunen[i];
                              return CheckboxListTile(
                                dense: true,
                                value: _secili.contains(a.id),
                                onChanged: (v) => setState(() {
                                  v == true
                                      ? _secili.add(a.id)
                                      : _secili.remove(a.id);
                                }),
                                title: Text(
                                  a.adi,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (a.telefonlar.isNotEmpty)
                                      a.telefonlar.first,
                                    if (a.var_) 'Rehberde kayıtlı',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (!_yukleniyor && !_izinYok && _liste.isNotEmpty)
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
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _secili.isEmpty || _aktariliyor ? null : _aktar,
                  icon: _aktariliyor
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text('${_secili.length} kişiyi rehbere ekle'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
