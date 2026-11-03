import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_istemci.dart';
import '../../veri/yazisma.dart';

/// Yazıyı gönderme seçenekleri: PDF / Word dosyası, cihazdaki WhatsApp ve e-posta uygulamaları ve (yetkiliyse) sunucu üzerinden
/// PDF ekli e-posta ile WhatsApp hattı gönderimi (web ile aynı kurallar).
class YazismaGonder {
  YazismaGonder._();

  static Future<void> goster(
    BuildContext context, {
    required Yazisma yazisma,
    required YazismaReferans ref,
    required dynamic motor,
    required String duzMetin,
    required Future<void> Function() pdfAc,
    required Future<void> Function() wordAc,
    required void Function(String) mesaj,
  }) async {
    final api = motor.api as ApiIstemci;
    final secim = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Oge(c, 'pdf', Icons.picture_as_pdf_outlined, 'PDF olarak aç'),
            _Oge(c, 'word', Icons.description_outlined, 'Word olarak aç'),
            _Oge(
              c,
              'wa',
              Icons.chat_outlined,
              'WhatsApp uygulamasıyla gönder (metin)',
            ),
            _Oge(
              c,
              'mail',
              Icons.mail_outline_rounded,
              'E-posta uygulamasıyla gönder (metin)',
            ),
            if (ref.eposta)
              _Oge(
                c,
                'sunucu-eposta',
                Icons.forward_to_inbox_rounded,
                'E-posta gönder (PDF ekli, sunucu üzerinden)',
              ),
            if (ref.whatsapp)
              _Oge(
                c,
                'sunucu-wa',
                Icons.send_to_mobile_rounded,
                'WhatsApp hattıyla gönder (sunucu üzerinden)',
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (secim == null || !context.mounted) return;
    switch (secim) {
      case 'pdf':
        await pdfAc();
      case 'word':
        await wordAc();
      case 'wa':
        final u = Uri.parse(
          'https://api.whatsapp.com/send?text=${Uri.encodeComponent(duzMetin)}',
        );
        final tamam = await launchUrl(
          u,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
        if (!tamam) mesaj('WhatsApp açılamadı.');
      case 'mail':
        final u = Uri(
          scheme: 'mailto',
          query:
              'subject=${Uri.encodeComponent('Resmî yazı: ${yazisma.kisi}')}&body=${Uri.encodeComponent(duzMetin)}',
        );
        final tamam = await launchUrl(u).catchError((_) => false);
        if (!tamam) mesaj('E-posta uygulaması açılamadı.');
      case 'sunucu-eposta':
      case 'sunucu-wa':
        final no = yazisma.no;
        if (no == null) {
          mesaj(
            'Yazı henüz sunucuya gönderilmedi; senkron bittikten sonra deneyin.',
          );
          return;
        }
        Map<String, dynamic> sec;
        try {
          sec = await api.get('yazismalar/gonder-secenekleri?no=$no');
        } on ApiHata catch (e) {
          mesaj(
            e.agHatasi ? 'Gönderim için internet bağlantısı gerekir.' : e.mesaj,
          );
          return;
        }
        if (!context.mounted) return;
        final sonuc = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (c) => secim == 'sunucu-eposta'
              ? _EpostaFormu(api: api, no: no, sec: sec)
              : _WaFormu(api: api, no: no, sec: sec),
        );
        if (sonuc != null) mesaj(sonuc);
    }
  }
}

class _Oge extends StatelessWidget {
  const _Oge(this.c, this.deger, this.ikon, this.baslik);

  final BuildContext c;
  final String deger;
  final IconData ikon;
  final String baslik;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(ikon),
    title: Text(baslik),
    onTap: () => Navigator.pop(c, deger),
  );
}

class _EpostaFormu extends StatefulWidget {
  const _EpostaFormu({required this.api, required this.no, required this.sec});

  final ApiIstemci api;
  final int no;
  final Map<String, dynamic> sec;

  @override
  State<_EpostaFormu> createState() => _EpostaFormuState();
}

class _EpostaFormuState extends State<_EpostaFormu> {
  final _form = GlobalKey<FormState>();
  final _kime = TextEditingController();
  late final _konu = TextEditingController(
    text: '${(widget.sec['eposta'] as Map?)?['konu'] ?? ''}',
  );
  late final _mesaj = TextEditingController(
    text: '${(widget.sec['eposta'] as Map?)?['mesaj'] ?? ''}',
  );
  int? _hesap;
  bool _gidiyor = false;
  String? _hata;

  List<Map<String, dynamic>> get _hesaplar => [
    for (final x
        in ((widget.sec['eposta'] as Map?)?['hesaplar'] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  @override
  void initState() {
    super.initState();
    final h = _hesaplar;
    if (h.isNotEmpty) {
      _hesap =
          (h.firstWhere(
                    (x) => x['varsayilan'] == true,
                    orElse: () => h.first,
                  )['no']
                  as num)
              .toInt();
    }
  }

  @override
  void dispose() {
    _kime.dispose();
    _konu.dispose();
    _mesaj.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _gidiyor = true;
      _hata = null;
    });
    try {
      final v = await widget.api.post(
        'yazismalar/gonder-eposta',
        govde: {
          'no': widget.no,
          'hesap': _hesap,
          'kime': _kime.text.trim(),
          'konu': _konu.text.trim(),
          'mesaj': _mesaj.text.trim(),
        },
      );
      if (mounted) {
        Navigator.pop(context, '${v['message'] ?? 'E-posta kuyruğa alındı.'}');
      }
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _gidiyor = false;
          _hata = e.agHatasi ? 'İnternet bağlantısı yok.' : e.mesaj;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hesaplar = _hesaplar;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'E-posta ile gönder (PDF ekli)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                if (hesaplar.isEmpty)
                  const Text(
                    'Tanımlı e-posta hesabınız yok. Web panelinden E-posta modülünde hesap ekleyin.',
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _hesap,
                    isExpanded: true,
                    hint: const Text('Seçiniz'),
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Gönderen hesap *',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    items: [
                      for (final h in hesaplar)
                        DropdownMenuItem(
                          value: (h['no'] as num).toInt(),
                          child: Text(
                            '${h['etiket']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _hesap = v),
                    validator: (v) => v == null ? 'Hesap seçin' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _kime,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Alıcı *',
                      hintText: 'ornek@kurum.gov.tr',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Geçerli bir e-posta adresi girin'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _konu,
                    decoration: const InputDecoration(
                      labelText: 'Konu *',
                      prefixIcon: Icon(Icons.subject_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Konu boş olamaz'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _mesaj,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Mesaj',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
                if (_hata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _hata!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (_gidiyor || hesaplar.isEmpty) ? null : _gonder,
                  icon: _gidiyor
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Gönder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaFormu extends StatefulWidget {
  const _WaFormu({required this.api, required this.no, required this.sec});

  final ApiIstemci api;
  final int no;
  final Map<String, dynamic> sec;

  @override
  State<_WaFormu> createState() => _WaFormuState();
}

class _WaFormuState extends State<_WaFormu> {
  final _form = GlobalKey<FormState>();
  final _numara = TextEditingController();
  late final _metin = TextEditingController(
    text: '${(widget.sec['whatsapp'] as Map?)?['kisa'] ?? ''}',
  );
  int? _hat;
  bool _pdf = true;
  bool _gidiyor = false;
  String? _hata;

  List<Map<String, dynamic>> get _hatlar => [
    for (final x
        in ((widget.sec['whatsapp'] as Map?)?['hatlar'] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  @override
  void initState() {
    super.initState();
    final h = _hatlar;
    if (h.isNotEmpty) {
      _hat =
          (h.firstWhere((x) => x['bagli'] == true, orElse: () => h.first)['no']
                  as num)
              .toInt();
    }
  }

  @override
  void dispose() {
    _numara.dispose();
    _metin.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _gidiyor = true;
      _hata = null;
    });
    try {
      final v = await widget.api.post(
        'yazismalar/gonder-whatsapp',
        govde: {
          'no': widget.no,
          'hat_no': _hat,
          'numara': _numara.text.trim(),
          'metin': _metin.text.trim(),
          'pdf': _pdf ? 1 : 0,
        },
      );
      if (mounted) {
        Navigator.pop(
          context,
          '${v['message'] ?? 'WhatsApp mesajı gönderildi.'}',
        );
      }
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _gidiyor = false;
          _hata = e.agHatasi ? 'İnternet bağlantısı yok.' : e.mesaj;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hatlar = _hatlar;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'WhatsApp ile gönder',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                if (hatlar.isEmpty)
                  const Text(
                    'Kullanabileceğiniz WhatsApp hattı yok. Web panelinde WhatsApp > Hatlarım sayfasından hat ekleyin.',
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _hat,
                    isExpanded: true,
                    hint: const Text('Seçiniz'),
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Hat *',
                      prefixIcon: Icon(Icons.sim_card_outlined),
                    ),
                    items: [
                      for (final h in hatlar)
                        DropdownMenuItem(
                          value: (h['no'] as num).toInt(),
                          child: Text(
                            '${h['ad']}${h['bagli'] == true ? '' : ' (bağlı değil)'}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _hat = v),
                    validator: (v) => v == null ? 'Hat seçin' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _numara,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefon *',
                      hintText: '0532 123 45 67',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'Geçerli bir telefon numarası girin'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _metin,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Mesaj *',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Mesaj boş olamaz'
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Yazıyı PDF olarak ekle'),
                    value: _pdf,
                    onChanged: (v) => setState(() => _pdf = v),
                  ),
                ],
                if (_hata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _hata!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (_gidiyor || hatlar.isEmpty) ? null : _gonder,
                  icon: _gidiyor
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Gönder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
