import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_istemci.dart';
import '../../diger/modul_hero.dart';
import '../../veri/bakanlik.dart';
import '../programlar/program_ortak.dart';

/// Değişiklik / yeni kurum / kaldırma önerisi formu. Öneri bağlantı ister; yönetici onayından sonra ortak listeye yansır.
/// Başarıyla gönderilirse sayfa kapanırken kullanıcıya gösterilecek mesajı döndürür.
class BakanlikOneriFormu extends StatefulWidget {
  const BakanlikOneriFormu({
    super.key,
    required this.servis,
    required this.tip,
    required this.katNo,
    required this.bakanlikAdi,
    required this.bakanliklar,
    this.kurum,
  });

  final BakanlikServisi servis;

  /// degistir | ekle | kaldir
  final String tip;
  final int katNo;
  final String bakanlikAdi;
  final List<Bakanlik> bakanliklar;
  final Kurum? kurum;

  @override
  State<BakanlikOneriFormu> createState() => _BakanlikOneriFormuState();
}

class _BakanlikOneriFormuState extends State<BakanlikOneriFormu> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in [
      'yeni_adi',
      'yeni_unvan',
      'yeni_telefon',
      'yeni_dahili',
      'yeni_telefon2',
      'yeni_dahili2',
      'yeni_faks',
      'yeni_eposta',
      'aciklama',
    ])
      k: TextEditingController(),
  };
  bool _gonderiliyor = false;
  String? _hata;
  late int _kat = widget.katNo; // yeni kurumda seçilen bakanlık (zorunlu)

  bool get _kaldir => widget.tip == 'kaldir';

  @override
  void initState() {
    super.initState();
    final k = widget.kurum;
    if (k != null && widget.tip == 'degistir') {
      _c['yeni_adi']!.text = k.adi;
      _c['yeni_unvan']!.text = k.unvan;
      _c['yeni_telefon']!.text = k.telefon;
      _c['yeni_dahili']!.text = k.dahili;
      _c['yeni_telefon2']!.text = k.telefon2;
      _c['yeni_dahili2']!.text = k.dahili2;
      _c['yeni_faks']!.text = k.faks;
      _c['yeni_eposta']!.text = k.eposta;
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gonder() async {
    if (_gonderiliyor) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _gonderiliyor = true;
      _hata = null;
    });
    try {
      final govde = <String, dynamic>{
        'tip': widget.tip,
        if (widget.tip == 'ekle')
          'bk_katno': widget.katNo
        else
          'bk_no': widget.kurum!.no,
        for (final e in _c.entries) e.key: e.value.text.trim(),
      };
      final m = await widget.servis.oner(govde);
      if (mounted) Navigator.of(context).pop(m);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _gonderiliyor = false;
          _hata = e.agHatasi
              ? 'Öneri göndermek için internet bağlantısı gerekir.'
              : e.mesaj;
        });
      }
    }
  }

  String get _baslik => switch (widget.tip) {
    'ekle' => 'YENİ KURUM ÖNER',
    'kaldir' => 'KALDIRILMASINI ÖNER',
    _ => 'DEĞİŞİKLİK ÖNER',
  };

  Widget _alan(
    String k,
    String etiket, {
    TextInputType tur = TextInputType.text,
    int satir = 1,
    List<TextInputFormatter>? bicim,
    String? Function(String?)? dogrula,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _c[k],
      keyboardType: tur,
      minLines: satir,
      maxLines: satir == 1 ? 1 : 5,
      inputFormatters: bicim,
      validator: dogrula,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: etiket),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final k = widget.kurum;
    final telBicim = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-. /]')),
    ];
    final rakam = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: true,
            ikon: Icons.lightbulb_outline,
            baslik: _baslik,
            altBaslik: widget.tip == 'ekle'
                ? 'Bakanlığı seçip yeni kurum önerin'
                : (widget.bakanlikAdi.isEmpty
                      ? 'Bakanlık'
                      : widget.bakanlikAdi),
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
              child: Form(
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
                            if (k != null)
                              ProgramKutu(
                                baslik: 'Mevcut kayıt',
                                ikon: Icons.corporate_fare_outlined,
                                cocuk: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      k.baslik,
                                      style: tema.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (k.altBaslik.isNotEmpty)
                                      Text(k.altBaslik),
                                    if (k.telefon.isNotEmpty)
                                      Text(
                                        k.telefon,
                                        style: TextStyle(color: cs.primary),
                                      ),
                                  ],
                                ),
                              ),
                            if (widget.tip == 'ekle')
                              ProgramKutu(
                                baslik: 'Bakanlık',
                                ikon: Icons.account_balance_outlined,
                                cocuk: DropdownButtonFormField<int>(
                                  isExpanded: true,
                                  initialValue:
                                      widget.bakanliklar.any(
                                        (b) => b.no == _kat,
                                      )
                                      ? _kat
                                      : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Bakanlık *',
                                  ),
                                  items: [
                                    for (final b in widget.bakanliklar)
                                      DropdownMenuItem(
                                        value: b.no,
                                        child: Text(
                                          b.adi,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  validator: (v) => v == null
                                      ? 'Bakanlık seçmelisiniz.'
                                      : null,
                                  onChanged: (v) {
                                    if (v != null) setState(() => _kat = v);
                                  },
                                ),
                              ),
                            if (_kaldir)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'Bu kaydın listeden kaldırılması için yöneticiye öneri gönderilecek. Nedenini yazmanız onayı hızlandırır.',
                                  style: tema.textTheme.bodyMedium,
                                ),
                              )
                            else
                              ProgramKutu(
                                baslik: widget.tip == 'ekle'
                                    ? 'Yeni kurum bilgileri'
                                    : 'Yeni bilgiler',
                                ikon: Icons.edit_note_rounded,
                                cocuk: Column(
                                  children: [
                                    _alan('yeni_unvan', 'Ünvan'),
                                    _alan('yeni_adi', 'Adı soyadı / kurum adı'),
                                    _alan(
                                      'yeni_telefon',
                                      'Telefon',
                                      tur: TextInputType.phone,
                                      bicim: telBicim,
                                    ),
                                    _alan(
                                      'yeni_dahili',
                                      'Dahili',
                                      tur: TextInputType.number,
                                      bicim: rakam,
                                    ),
                                    _alan(
                                      'yeni_telefon2',
                                      'Telefon 2',
                                      tur: TextInputType.phone,
                                      bicim: telBicim,
                                    ),
                                    _alan(
                                      'yeni_dahili2',
                                      'Dahili 2',
                                      tur: TextInputType.number,
                                      bicim: rakam,
                                    ),
                                    _alan(
                                      'yeni_faks',
                                      'Faks',
                                      tur: TextInputType.phone,
                                      bicim: telBicim,
                                    ),
                                    _alan(
                                      'yeni_eposta',
                                      'E-posta',
                                      tur: TextInputType.emailAddress,
                                      dogrula: (v) {
                                        final t = (v ?? '').trim();
                                        if (t.isEmpty) return null;
                                        return RegExp(
                                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                            ).hasMatch(t)
                                            ? null
                                            : 'E-posta adresi geçersiz.';
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ProgramKutu(
                              baslik: 'Açıklama',
                              ikon: Icons.notes_rounded,
                              cocuk: _alan(
                                'aciklama',
                                _kaldir
                                    ? 'Neden kaldırılsın?'
                                    : 'Açıklama (isteğe bağlı)',
                                satir: 3,
                              ),
                            ),
                            if (_hata != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  _hata!,
                                  style: TextStyle(color: cs.error),
                                ),
                              ),
                            SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: _gonderiliyor ? null : _gonder,
                                icon: _gonderiliyor
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                                label: const Text('Öneriyi gönder'),
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
        ],
      ),
    );
  }
}

/// Bu makamın önerileri: durum rozetli liste; bekleyenler iptal edilebilir.
class BakanlikOnerilerim extends StatefulWidget {
  const BakanlikOnerilerim({super.key, required this.servis});

  final BakanlikServisi servis;

  @override
  State<BakanlikOnerilerim> createState() => _BakanlikOnerilerimState();
}

class _BakanlikOnerilerimState extends State<BakanlikOnerilerim> {
  List<Map<String, dynamic>>? _liste;
  String? _hata;
  String _durum = '';

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _liste = null;
      _hata = null;
    });
    try {
      final l = await widget.servis.oneriler(durum: _durum);
      if (mounted) setState(() => _liste = l);
    } on ApiHata catch (e) {
      if (mounted) {
        setState(
          () => _hata = e.agHatasi
              ? 'Öneriler için internet bağlantısı gerekir.'
              : e.mesaj,
        );
      }
    }
  }

  Future<void> _iptal(int no) async {
    try {
      final m = await widget.servis.iptal(no);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(m)));
      }
      _yukle();
    } on ApiHata catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                e.agHatasi
                    ? 'İptal için internet bağlantısı gerekir.'
                    : e.mesaj,
              ),
            ),
          );
      }
    }
  }

  Color _renk(String d) => switch (d) {
    'bekliyor' => const Color(0xFFD97706),
    'onaylandi' => const Color(0xFF1F8A5B),
    'reddedildi' => const Color(0xFFE11D48),
    _ => const Color(0xFF64748B),
  };

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
          const ModulHero(
            geri: true,
            ikon: Icons.lightbulb_outline,
            baslik: 'ÖNERİLERİM',
            altBaslik: 'Bakanlık teşkilatları için gönderdikleriniz',
          ),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final d in const [
                  '',
                  'bekliyor',
                  'onaylandi',
                  'reddedildi',
                  'iptal',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(d.isEmpty ? 'Tümü' : oneriDurumAdi(d)),
                      selected: _durum == d,
                      onSelected: (_) {
                        _durum = d;
                        _yukle();
                      },
                    ),
                  ),
              ],
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
              child: _hata != null
                  ? Center(child: Text(_hata!))
                  : _liste == null
                  ? const Center(child: CircularProgressIndicator())
                  : _liste!.isEmpty
                  ? Center(
                      child: Text(
                        'Öneri yok',
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _liste!.length,
                          itemBuilder: (c, i) {
                            final o = _liste![i];
                            final d = '${o['durum']}';
                            final yeni = '${o['yeni_unvan']}'.isNotEmpty
                                ? '${o['yeni_unvan']}'
                                : '${o['yeni_adi']}';
                            final eski = '${o['eski_unvan']}'.isNotEmpty
                                ? '${o['eski_unvan']}'
                                : '${o['eski_adi']}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: programGolgesi(context),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${oneriTipAdi('${o['tip']}')} · ${o['bakanlik']}',
                                            style: tema.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _renk(d)
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            oneriDurumAdi(d),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: _renk(d),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      (o['tip'] == 'ekle' ? yeni : eski).isEmpty
                                          ? '—'
                                          : (o['tip'] == 'ekle' ? yeni : eski),
                                      style: tema.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (o['tip'] == 'degistir' &&
                                        yeni.isNotEmpty)
                                      Text('→ $yeni'),
                                    if ('${o['aciklama']}'.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '${o['aciklama']}',
                                          style: tema.textTheme.bodySmall,
                                        ),
                                      ),
                                    if ('${o['islem_notu']}'.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Yönetici notu: ${o['islem_notu']}',
                                          style: tema.textTheme.bodySmall
                                              ?.copyWith(
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                      ),
                                    if (d == 'bekliyor')
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () =>
                                              _iptal((o['no'] as num).toInt()),
                                          child: const Text('İptal et'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
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
