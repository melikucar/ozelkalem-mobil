import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../api/api_istemci.dart';
import 'rapor_ortak.dart';

/// Süzgeç panelindeki açılır seçim (kategori, durum, il, yer).
class RaporSecimi {
  const RaporSecimi({
    required this.etiket,
    required this.ikon,
    required this.liste,
    required this.deger,
    required this.degisti,
  });

  final String etiket;
  final IconData ikon;

  /// [{no, adi}]
  final List<Map<String, dynamic>> liste;
  final int deger;
  final RaporFiltre Function(RaporFiltre f, int v) degisti;
}

typedef RaporIcerik = List<Widget> Function(
  BuildContext context,
  Map<String, dynamic> veri,
  RaporFiltre filtre,
  void Function(RaporFiltre) uygula,
);

/// Üç raporun ortak çatısı: dönem şeritleri, özel aralık, süzgeçler, önceki dönemle karşılaştırma, CSV indirme,
/// yükleme / hata durumu ve çekince yenileme. İçeriği [icerik] çizer.
class RaporPaneli extends StatefulWidget {
  const RaporPaneli({
    super.key,
    required this.api,
    required this.tur,
    required this.secimler,
    required this.icerik,
    this.onYuklendi,
  });

  final ApiIstemci api;

  /// talep | faaliyet | ajanda
  final String tur;
  final List<RaporSecimi> Function(RaporFiltre f) secimler;
  final RaporIcerik icerik;
  final VoidCallback? onYuklendi;

  @override
  State<RaporPaneli> createState() => _RaporPaneliState();
}

class _RaporPaneliState extends State<RaporPaneli>
    with AutomaticKeepAliveClientMixin {
  RaporFiltre _f = const RaporFiltre();
  Map<String, dynamic>? _veri;
  bool _yukleniyor = true;
  String? _hata;
  int _istek = 0;
  bool _csv = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final q = Uri(queryParameters: {'tur': widget.tur, ..._f.sorgu}).query;
      final v = await widget.api.get('raporlar/istatistik?$q');
      if (!mounted || no != _istek) return;
      setState(() {
        _veri = v;
        _yukleniyor = false;
      });
      widget.onYuklendi?.call();
    } on ApiHata catch (e) {
      if (!mounted || no != _istek) return;
      setState(() {
        _yukleniyor = false;
        _hata = e.agHatasi
            ? 'Raporlar sunucuda hesaplanır; internet bağlantısı gerekir.'
            : (e.durum == 403 ? 'Raporlar için yetkiniz yok.' : e.mesaj);
      });
    }
  }

  void _uygula(RaporFiltre f) {
    setState(() => _f = f);
    _yukle();
  }

  Future<void> _ozelAralik() async {
    final simdi = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(simdi.year + 1, 12, 31),
      initialDateRange: _f.bas != null && _f.bit != null
          ? DateTimeRange(start: _f.bas!, end: _f.bit!)
          : DateTimeRange(
              start: simdi.subtract(const Duration(days: 29)),
              end: simdi,
            ),
      saveText: 'Uygula',
      helpText: 'Tarih aralığı',
    );
    if (r != null) _uygula(_f.kopya(donem: 'ozel', bas: r.start, bit: r.end));
  }

  Future<void> _suzgecler() async {
    final yeni = await showModalBottomSheet<RaporFiltre>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _SuzgecPaneli(f: _f, secimler: widget.secimler),
    );
    if (yeni != null) _uygula(yeni);
  }

  Future<void> _csvIndir() async {
    if (_csv) return;
    setState(() => _csv = true);
    try {
      final q = Uri(queryParameters: {'tur': widget.tur, ..._f.sorgu}).query;
      final r = await widget.api.dosyaIndir('raporlar/csv?$q');
      final dizin = Directory(
        p.join((await getTemporaryDirectory()).path, 'raporlar'),
      );
      if (!dizin.existsSync()) dizin.createSync(recursive: true);
      final yol = p.join(dizin.path, r.ad ?? '${widget.tur}-raporu.csv');
      await File(yol).writeAsBytes(r.bayt, flush: true);
      final s = await OpenFilex.open(yol, type: 'text/csv');
      if (s.type != ResultType.done && mounted) {
        _mesaj(
          s.type == ResultType.noAppToOpen
              ? 'CSV dosyasını açabilecek uygulama yok (Excel / Sheets kurun).'
              : 'Dosya açılamadı.',
        );
      }
    } on ApiHata catch (e) {
      _mesaj(
        e.agHatasi ? 'İndirmek için internet bağlantısı gerekir.' : e.mesaj,
      );
    } finally {
      if (mounted) setState(() => _csv = false);
    }
  }

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  String get _aralikMetni {
    final a = _veri?['aralik'];
    if (a is! Map) return donemAdi(_f.donem);
    return '${donemAdi('${a['donem']}')} · ${tarihTr(a['bas'])} – ${tarihTr(a['bit'])} (${sayi(a['gun'])} gün)';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final secimler = widget.secimler(_f);
    return Column(
      children: [
        _filtreCubugu(tema, cs),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _yukle,
            child: _govde(tema, cs, secimler),
          ),
        ),
      ],
    );
  }

  Widget _filtreCubugu(ThemeData tema, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in raporDonemleri)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(d.$2),
                      selected: _f.donem == d.$1,
                      onSelected: (_) => _uygula(_f.kopya(donem: d.$1)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 16),
                    label: Text(
                      _f.donem == 'ozel' && _f.bas != null
                          ? '${_f.bas!.day}.${_f.bas!.month} – ${_f.bit!.day}.${_f.bit!.month}.${_f.bit!.year}'
                          : 'Özel aralık',
                    ),
                    selected: _f.donem == 'ozel',
                    onSelected: (_) => _ozelAralik(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _aralikMetni,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      tooltip: 'Süzgeçler',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: _suzgecler,
                    ),
                    if (_f.etkin > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDEC290),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_f.etkin}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0C1C2F),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: 'Excel / CSV',
                  visualDensity: VisualDensity.compact,
                  icon: _csv
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  onPressed: _csvIndir,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _govde(ThemeData tema, ColorScheme cs, List<RaporSecimi> secimler) {
    if (_veri == null) {
      if (_hata != null) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 80, 40, 0),
              child: Column(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 52, color: cs.outline),
                  const SizedBox(height: 14),
                  Text(
                    _hata!,
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonal(
                    onPressed: _yukle,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final suzgerAktif = _f.etkin > 0;
    return Stack(
      children: [
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (suzgerAktif)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final s in secimler)
                              if (s.deger > 0)
                                InputChip(
                                  avatar: Icon(s.ikon, size: 15),
                                  label: Text(
                                    '${s.etiket}: ${s.liste.where((x) => x['no'] == s.deger).map((x) => x['adi']).firstOrNull ?? s.deger}',
                                  ),
                                  onDeleted: () => _uygula(s.degisti(_f, 0)),
                                ),
                            if (_f.il > 0 &&
                                !secimler.any((s) => s.etiket == 'İl'))
                              InputChip(
                                avatar: const Icon(
                                  Icons.place_outlined,
                                  size: 15,
                                ),
                                label: const Text('İl süzgeci (harita)'),
                                onDeleted: () => _uygula(_f.kopya(il: 0)),
                              ),
                            ActionChip(
                              label: const Text('Tümünü temizle'),
                              onPressed: () => _uygula(
                                RaporFiltre(
                                  donem: _f.donem,
                                  bas: _f.bas,
                                  bit: _f.bit,
                                  karsilastir: _f.karsilastir,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...widget.icerik(context, _veri!, _f, _uygula),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_yukleniyor)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }
}

class _SuzgecPaneli extends StatefulWidget {
  const _SuzgecPaneli({required this.f, required this.secimler});

  final RaporFiltre f;
  final List<RaporSecimi> Function(RaporFiltre f) secimler;

  @override
  State<_SuzgecPaneli> createState() => _SuzgecPaneliState();
}

class _SuzgecPaneliState extends State<_SuzgecPaneli> {
  late RaporFiltre _f = widget.f;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Süzgeçler', style: tema.textTheme.titleMedium),
              const SizedBox(height: 14),
              for (final s in widget.secimler(_f))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<int>(
                    initialValue: s.liste.any((x) => x['no'] == s.deger)
                        ? s.deger
                        : 0,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: s.etiket,
                      prefixIcon: Icon(s.ikon),
                    ),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Tümü')),
                      for (final x in s.liste)
                        DropdownMenuItem(
                          value: (x['no'] as num).toInt(),
                          child: Text(
                            '${x['adi']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _f = s.degisti(_f, v ?? 0)),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Önceki dönemle karşılaştır'),
                value: _f.karsilastir,
                onChanged: (v) => setState(() => _f = _f.kopya(karsilastir: v)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        RaporFiltre(
                          donem: _f.donem,
                          bas: _f.bas,
                          bit: _f.bit,
                          karsilastir: _f.karsilastir,
                        ),
                      ),
                      child: const Text('Temizle'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _f),
                      child: const Text('Uygula'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
