import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../veri/talep_deposu.dart';
import '../../veri/talep_filtre.dart';
import '../../veri/tarih_yardimci.dart';
import '../../diger/alanlar.dart';
import 'talepler_listesi.dart' show talepRengi;

/// Gelişmiş filtre paneli (alttan açılır): sıralama, durum, kategori, tarih, ilçe, kaydeden, telefon ve hızlı seçenekler.
/// "Uygula" ile yeni filtre döner, kapatılırsa null. Altta, seçimlerle anında güncellenen sonuç sayısı görünür.
Future<TalepFiltre?> talepFiltrePaneli(
  BuildContext context, {
  required TalepDeposu depo,
  required TalepFiltre mevcut,
  required Map<int, ({String adi, String? renk})> durumlar,
  required Map<int, String> kategoriler,
}) {
  return showModalBottomSheet<TalepFiltre>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.94,
    ),
    builder: (_) => _FiltrePaneli(
      depo: depo,
      mevcut: mevcut,
      durumlar: durumlar,
      kategoriler: kategoriler,
    ),
  );
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _FiltrePaneli extends StatefulWidget {
  const _FiltrePaneli({
    required this.depo,
    required this.mevcut,
    required this.durumlar,
    required this.kategoriler,
  });

  final TalepDeposu depo;
  final TalepFiltre mevcut;
  final Map<int, ({String adi, String? renk})> durumlar;
  final Map<int, String> kategoriler;

  @override
  State<_FiltrePaneli> createState() => _FiltrePaneliState();
}

class _FiltrePaneliState extends State<_FiltrePaneli> {
  late TalepFiltre _f = widget.mevcut;
  late final _telefon = TextEditingController(text: widget.mevcut.telefon);
  int? _sonuc;
  int _sayimNo = 0;

  List<({int id, String ad, int adet})> _ilceler = [];
  List<({int no, String adi})> _kaydedenler = [];

  @override
  void initState() {
    super.initState();
    _sayiGuncelle();
    widget.depo.ilceSecenekleri().then((l) {
      if (mounted) setState(() => _ilceler = l);
    });
    widget.depo.kaydedenler().then((l) {
      if (mounted) setState(() => _kaydedenler = l);
    });
  }

  @override
  void dispose() {
    _telefon.dispose();
    super.dispose();
  }

  void _degistir(TalepFiltre yeni) {
    setState(() => _f = yeni);
    _sayiGuncelle();
  }

  Future<void> _sayiGuncelle() async {
    final no = ++_sayimNo;
    final n = await widget.depo.sonucSayisi(_f);
    if (mounted && no == _sayimNo) setState(() => _sonuc = n);
  }

  Future<void> _tarihSec(bool baslangic) async {
    final simdi = DateTime.now();
    final ilk = DateTime.tryParse((baslangic ? _f.bas : _f.bit) ?? '') ?? simdi;
    final d = await showDatePicker(
      context: context,
      initialDate: ilk,
      firstDate: DateTime(2000),
      lastDate: DateTime(simdi.year + 2),
      helpText: baslangic ? 'Başlangıç tarihi' : 'Bitiş tarihi',
    );
    if (d == null) return;
    _degistir(baslangic ? _f.kopya(bas: _iso(d)) : _f.kopya(bit: _iso(d)));
  }

  void _hazirTarih(String tur) {
    final n = DateTime.now();
    final bugun = DateTime(n.year, n.month, n.day);
    switch (tur) {
      case 'bugun':
        _degistir(_f.kopya(bas: _iso(bugun), bit: _iso(bugun)));
      case 'hafta':
        _degistir(
          _f.kopya(
            bas: _iso(bugun.subtract(const Duration(days: 6))),
            bit: _iso(bugun),
          ),
        );
      case 'ay':
        _degistir(
          _f.kopya(bas: _iso(DateTime(n.year, n.month, 1)), bit: _iso(bugun)),
        );
      case 'yil':
        _degistir(
          _f.kopya(bas: _iso(DateTime(n.year, 1, 1)), bit: _iso(bugun)),
        );
      default:
        _degistir(_f.kopya(bas: null, bit: null));
    }
  }

  bool _hazirSecili(String tur) {
    final n = DateTime.now();
    final bugun = DateTime(n.year, n.month, n.day);
    return switch (tur) {
      'bugun' => _f.bas == _iso(bugun) && _f.bit == _iso(bugun),
      'hafta' =>
        _f.bas == _iso(bugun.subtract(const Duration(days: 6))) &&
            _f.bit == _iso(bugun),
      'ay' =>
        _f.bas == _iso(DateTime(n.year, n.month, 1)) && _f.bit == _iso(bugun),
      'yil' => _f.bas == _iso(DateTime(n.year, 1, 1)) && _f.bit == _iso(bugun),
      _ => false,
    };
  }

  void _temizle() {
    _telefon.clear();
    _degistir(TalepFiltre(arama: _f.arama, sirala: TalepSirala.yeni));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final alt = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: alt),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filtreler',
                    style: tema.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _temizle,
                  icon: const Icon(Icons.restart_alt_rounded, size: 19),
                  label: const Text('Temizle'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                if (widget.durumlar.isNotEmpty) ...[
                  _Secim(
                    etiket: 'Durum',
                    ikon: Icons.flag_outlined,
                    secili: _f.durumlar,
                    secenekler: [
                      for (final e in widget.durumlar.entries)
                        (
                          no: e.key,
                          ad: e.value.adi,
                          renk:
                              talepRengi(e.value.renk) ??
                              tema.colorScheme.outline,
                        ),
                    ],
                    degisti: (k) => _degistir(_f.kopya(durumlar: k)),
                  ),
                ],
                if (widget.kategoriler.isNotEmpty) ...[
                  _Secim(
                    etiket: 'Kategori',
                    ikon: Icons.category_outlined,
                    secili: _f.kategoriler,
                    secenekler: [
                      for (final e in widget.kategoriler.entries)
                        (no: e.key, ad: e.value, renk: null),
                    ],
                    degisti: (k) => _degistir(_f.kopya(kategoriler: k)),
                  ),
                ],
                _Baslik('Tarih aralığı', Icons.date_range_outlined),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final h in const [
                      ('bugun', 'Bugün'),
                      ('hafta', 'Son 7 gün'),
                      ('ay', 'Bu ay'),
                      ('yil', 'Bu yıl'),
                    ])
                      ChoiceChip(
                        label: Text(h.$2),
                        selected: _hazirSecili(h.$1),
                        onSelected: (v) => _hazirTarih(v ? h.$1 : 'hepsi'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _TarihKutusu(
                        etiket: 'Başlangıç',
                        deger: _f.bas,
                        tikla: () => _tarihSec(true),
                        temizle: () => _degistir(_f.kopya(bas: null)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TarihKutusu(
                        etiket: 'Bitiş',
                        deger: _f.bit,
                        tikla: () => _tarihSec(false),
                        temizle: () => _degistir(_f.kopya(bit: null)),
                      ),
                    ),
                  ],
                ),
                if (_ilceler.isNotEmpty || _kaydedenler.isNotEmpty) ...[
                  _Baslik('Kişi ve yer', Icons.place_outlined),
                  if (_ilceler.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SecimAlani<int>(
                        key: ValueKey('ilce-${_f.ilce}'),
                        etiket: 'İlçe',
                        ikon: Icons.map_outlined,
                        initialValue: _f.ilce,
                        bos: 'Tümü',
                        gorunenAd: _f.ilce == null
                            ? null
                            : _ilceler
                                      .where((i) => i.id == _f.ilce)
                                      .firstOrNull
                                      ?.ad ??
                                  '${_f.ilce}',
                        liste: () async => [
                          for (final i in _ilceler)
                            SecimOgesi<int>(i.id, '${i.ad} (${i.adet})'),
                        ],
                        degisti: (v) => _degistir(_f.kopya(ilce: v)),
                      ),
                    ),
                  if (_kaydedenler.isNotEmpty)
                    SecimAlani<int>(
                      key: ValueKey('kaydeden-${_f.kaydeden}'),
                      etiket: 'Kaydeden',
                      ikon: Icons.badge_outlined,
                      initialValue: _f.kaydeden,
                      bos: 'Tümü',
                      gorunenAd: _f.kaydeden == null
                          ? null
                          : _kaydedenler
                                    .where((k) => k.no == _f.kaydeden)
                                    .firstOrNull
                                    ?.adi ??
                                '${_f.kaydeden}',
                      liste: () async => [
                        for (final k in _kaydedenler)
                          SecimOgesi<int>(k.no, k.adi),
                      ],
                      degisti: (v) => _degistir(_f.kopya(kaydeden: v)),
                    ),
                ],
                _Baslik('Telefon', Icons.phone_outlined),
                TextField(
                  controller: _telefon,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()+-]')),
                  ],
                  onChanged: (v) => _degistir(_f.kopya(telefon: v)),
                  decoration: InputDecoration(
                    hintText: 'Numaranın bir bölümünü yazın',
                    prefixIcon: const Icon(Icons.dialpad_rounded),
                    suffixIcon: _telefon.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _telefon.clear();
                              _degistir(_f.kopya(telefon: ''));
                            },
                          ),
                  ),
                ),
                _Baslik('Hızlı seçenekler', Icons.bolt_outlined),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gönderilmeyi bekleyenler'),
                  subtitle: const Text(
                    'Henüz sunucuya ulaşmamış değişiklikler',
                  ),
                  value: _f.bekleyen,
                  onChanged: (v) => _degistir(_f.kopya(bekleyen: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hatırlatıcılı talepler'),
                  value: _f.hatirlatici,
                  onChanged: (v) => _degistir(_f.kopya(hatirlatici: v)),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.paddingOf(context).bottom * 0,
            ),
            decoration: BoxDecoration(
              color: tema.colorScheme.surface,
              border: Border(
                top: BorderSide(color: tema.colorScheme.outlineVariant),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _f),
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  _sonuc == null
                      ? 'Uygula'
                      : _sonuc == 0
                      ? 'Sonuç yok'
                      : '$_sonuc kaydı göster',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek seçimli açılır liste; seçim kümesi tek öğeli ya da boş ("Hepsi") olur. Dışarıdan çoklu gelen seçim "N seçili" gösterilir.
class _Secim extends StatelessWidget {
  const _Secim({
    required this.etiket,
    required this.ikon,
    required this.secili,
    required this.secenekler,
    required this.degisti,
  });

  final String etiket;
  final IconData ikon;
  final Set<int> secili;
  final List<({int no, String ad, Color? renk})> secenekler;
  final ValueChanged<Set<int>> degisti;

  @override
  Widget build(BuildContext context) {
    const coklu = -1;
    final deger = secili.isEmpty
        ? 0
        : secili.length == 1
        ? secili.first
        : coklu;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$etiket-$deger'),
        initialValue: deger,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiket, prefixIcon: Icon(ikon)),
        items: [
          const DropdownMenuItem(value: 0, child: Text('Tümü')),
          if (deger == coklu)
            DropdownMenuItem(
              value: coklu,
              child: Text('${secili.length} seçili'),
            ),
          for (final o in secenekler)
            DropdownMenuItem(
              value: o.no,
              child: Row(
                children: [
                  if (o.renk != null) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: o.renk,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(child: Text(o.ad, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
        ],
        onChanged: (v) {
          if (v == null || v == coklu) return;
          degisti(v == 0 ? <int>{} : {v});
        },
      ),
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin, this.ikon);

  final String metin;
  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Icon(ikon, size: 18, color: tema.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            metin,
            style: tema.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarihKutusu extends StatelessWidget {
  const _TarihKutusu({
    required this.etiket,
    required this.deger,
    required this.tikla,
    required this.temizle,
  });

  final String etiket;
  final String? deger;
  final VoidCallback tikla;
  final VoidCallback temizle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: tikla,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiket,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          suffixIcon: deger == null
              ? const Icon(Icons.calendar_month_outlined)
              : IconButton(icon: const Icon(Icons.clear), onPressed: temizle),
        ),
        child: Text(
          uzunTarih(deger) ?? 'Seçilmedi',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: deger == null
                ? tema.colorScheme.onSurfaceVariant
                : tema.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
