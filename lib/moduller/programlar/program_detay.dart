import '../../diger/kompakt_dugme.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_istemci.dart';
import '../../veri/program.dart';
import '../../veri/program_deposu.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/dosya_islemleri.dart';
import '../../diger/modul_hero.dart';
import 'program_formu.dart';
import 'program_ortak.dart';

/// Program ayrıntısı (salt okunur): zaman, yer (haritada aç), notlar, hatırlatıcılar ve durumları, ekler, kayıt bilgileri.
/// Buradan düzenlenir, silinir, takvime eklenir (.ics). Sunucu ayrıntıları bağlantı varken indirilip saklanır.
class ProgramDetay extends StatefulWidget {
  const ProgramDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<ProgramDetay> createState() => _ProgramDetayState();
}

class _ProgramDetayState extends State<ProgramDetay> {
  Program? _p;
  KuyrukOp? _sorun;
  List<KuyrukOp> _dosyaIslemleri = [];
  Map<String, dynamic>? _ek;
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _ekHata = false;

  ProgramDeposu get _depo => widget.veri.programlar;

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
    final p = await _depo.getir(widget.yerelId);
    final s = (await _depo.sorunlular())[widget.yerelId];
    final d = await _depo.dosyaIslemleri(widget.yerelId);
    final ek = p?.no == null ? null : await _depo.ekOku(p!.no!);
    if (!mounted) return;
    if (p == null || p.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ilk = !_yuklendi;
    setState(() {
      _p = p;
      _sorun = s;
      _dosyaIslemleri = d;
      _ek = ek;
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _p?.no;
    final senk = widget.veri.motor.programSenkron;
    if (no == null || senk == null) return;
    setState(() {
      _ekYukleniyor = true;
      _ekHata = false;
    });
    try {
      final v = await senk.ayrintiGetir(no);
      if (mounted) setState(() => _ek = v);
    } on ApiHata {
      if (mounted) setState(() => _ekHata = true);
    } finally {
      if (mounted) setState(() => _ekYukleniyor = false);
    }
  }

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProgramFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Program silinsin mi?'),
        content: const Text(
          'Program, ekleri ve hatırlatıcılarıyla birlikte çöp kutusuna taşınır (web panelinden geri alınabilir).',
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

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  /// .ics dosyasını indirip telefondaki takvim uygulamasıyla açar.
  Future<void> _takvimeEkle() async {
    final no = _p?.no;
    if (no == null) {
      _mesaj(
        'Program henüz sunucuya gönderilmedi; gönderilince takvime eklenebilir.',
      );
      return;
    }
    try {
      final d = await widget.veri.motor.api.dosyaIndir('programlar/ics?no=$no');
      final dizin = await getTemporaryDirectory();
      final yol = '${dizin.path}/program-$no.ics';
      await File(yol).writeAsBytes(d.bayt);
      final s = await OpenFilex.open(yol, type: 'text/calendar');
      if (s.type != ResultType.done && mounted) {
        _mesaj('Takvim uygulaması bulunamadı.');
      }
    } on ApiHata catch (e) {
      _mesaj(
        e.agHatasi
            ? 'Takvime eklemek için internet bağlantısı gerekir.'
            : e.mesaj,
      );
    } catch (_) {
      _mesaj('Takvime eklenemedi.');
    }
  }

  Future<void> _haritadaAc() async {
    final yer = _p?.yer.trim() ?? '';
    if (yer.isEmpty) return;
    final q = Uri.encodeComponent(yer);
    var tamam = await launchUrl(
      Uri.parse('geo:0,0?q=$q'),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!tamam) {
      tamam = await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false);
    }
    if (!tamam && mounted) _mesaj('Harita açılamadı.');
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
    final p = _p;
    if (!_yuklendi || p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final ek = _ek;
    final renk = p.renk;
    final durum = programZamaniDurumu(p);
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
    final sunucuHat = [
      for (final x in (ek?['hatirlaticilar'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
    final yerelHat = p.hatirlatici;

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
            ikon: Icons.event_outlined,
            baslik: 'PROGRAM DETAYI',
            altBaslik: uzunGunYaz(p.bas),
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
                  if (v == 'duzenle') _duzenle();
                  if (v == 'ics') _takvimeEkle();
                  if (v == 'yenile') _ekiYenile();
                  if (v == 'sil') _sil();
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
                    value: 'ics',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.calendar_month_outlined),
                      title: Text('Takvime ekle (.ics)'),
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
                          if (ek == null && p.no != null && !_ekYukleniyor)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _Bilgi(
                                metin: _ekHata
                                    ? 'Kaydeden, hatırlatıcı durumu ve dosyalar için bağlantı gerekir. Bağlantı gelince yenileyin.'
                                    : 'Kaydeden, hatırlatıcı durumu ve dosyalar yükleniyor…',
                                eylem: _ekHata
                                    ? TextButton(
                                        onPressed: _ekiYenile,
                                        child: const Text('Yenile'),
                                      )
                                    : null,
                              ),
                            ),
                          _OzetKarti(
                            program: p,
                            durum: durum,
                            randevu: ek?['randevu'] as String?,
                          ),
                          _EylemSatiri(
                            yerVar: p.yer.trim().isNotEmpty,
                            harita: _haritadaAc,
                            takvim: _takvimeEkle,
                          ),
                          ProgramKutu(
                            baslik: 'Zaman',
                            ikon: Icons.schedule_rounded,
                            cocuk: Column(
                              children: [
                                _Satir(
                                  Icons.play_circle_outline_rounded,
                                  'Başlangıç',
                                  '${uzunGunYaz(p.bas)} · ${saatYaz(p.bas)}',
                                ),
                                const _Ayirac(),
                                _Satir(
                                  Icons.stop_circle_outlined,
                                  'Bitiş',
                                  '${uzunGunYaz(p.bit)} · ${saatYaz(p.bit)}',
                                ),
                                const _Ayirac(),
                                _Satir(
                                  Icons.timelapse_rounded,
                                  'Süre',
                                  sureYaz(p.bit.difference(p.bas)),
                                ),
                              ],
                            ),
                          ),
                          if (p.yer.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Yer',
                              ikon: Icons.place_outlined,
                              cocuk: SelectableText(
                                p.yer,
                                style: tema.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          if (p.notlar.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Notlar',
                              ikon: Icons.notes_rounded,
                              cocuk: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  12,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: renk.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border(
                                    left: BorderSide(color: renk, width: 3.5),
                                  ),
                                ),
                                child: SelectableText(
                                  p.notlar,
                                  style: tema.textTheme.bodyLarge?.copyWith(
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ProgramKutu(
                            baslik: 'Hatırlatıcılar',
                            ikon: Icons.notifications_active_outlined,
                            sag: _SayiRozeti(
                              sunucuHat.isNotEmpty
                                  ? sunucuHat.length
                                  : (yerelHat?.dakikalar.length ?? 0),
                            ),
                            cocuk: _hatirlaticilar(
                              tema,
                              sunucuHat,
                              yerelHat,
                              ek != null,
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Ek dosyalar',
                            ikon: Icons.attach_file_rounded,
                            sag: _SayiRozeti(
                              sunucuDosyalari.length +
                                  bekleyenYuklemeler.length,
                            ),
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (sunucuDosyalari.isEmpty &&
                                    bekleyenYuklemeler.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      ek == null
                                          ? 'Bağlantı kurulunca yüklenir'
                                          : 'Ek dosya yok',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                for (final d in sunucuDosyalari)
                                  DosyaSatiri(
                                    ad: '${d['goruntu']}',
                                    boyut: d['boyut'] as int?,
                                    etiket: silinecekler.contains(d['ad'])
                                        ? 'silinecek'
                                        : null,
                                    tikla: p.no == null
                                        ? null
                                        : () => sunucuDosyasiniAc(
                                            context,
                                            widget.veri.motor.api,
                                            p.no!,
                                            '${d['ad']}',
                                            '${d['goruntu']}',
                                            modul: 'programlar',
                                          ),
                                  ),
                                for (final o in bekleyenYuklemeler)
                                  DosyaSatiri(
                                    ad: '${o.govde['ad']}',
                                    boyut: (o.govde['boyut'] as num?)?.toInt(),
                                    etiket: 'gönderilecek',
                                    kaldir: () => _depo.dosyaIsleminiIptalEt(o),
                                  ),
                                const SizedBox(height: 6),
                                DosyaEkleDugmeleri(
                                  secildi: (l) async {
                                    for (final d in l) {
                                      await _depo.dosyaEkle(
                                        widget.yerelId,
                                        yol: d.yol,
                                        ad: d.ad,
                                        boyut: d.boyut,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Kayıt bilgileri',
                            ikon: Icons.history_toggle_off_rounded,
                            cocuk: ek == null
                                ? Text(
                                    'Bağlantı kurulunca yüklenir',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  )
                                : Column(
                                    children: [
                                      _Satir(
                                        Icons.person_outline_rounded,
                                        'Ekleyen',
                                        (ek['ekleyen'] as String?)
                                                    ?.isNotEmpty ==
                                                true
                                            ? ek['ekleyen'] as String
                                            : '—',
                                      ),
                                      const _Ayirac(),
                                      _Satir(
                                        Icons.add_circle_outline_rounded,
                                        'İlk kayıt',
                                        _kimNe(ek['ilk_kayit']),
                                      ),
                                      const _Ayirac(),
                                      _Satir(
                                        Icons.update_rounded,
                                        'Son güncelleme',
                                        ek['son_guncelleme'] == null
                                            ? 'Henüz güncellenmedi'
                                            : _kimNe(ek['son_guncelleme']),
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

  Widget _hatirlaticilar(
    ThemeData tema,
    List<Map<String, dynamic>> sunucu,
    HatirlaticiAyar? yerel,
    bool ekVar,
  ) {
    final cs = tema.colorScheme;
    if (sunucu.isNotEmpty && !_p!.bekleyen) {
      return Column(
        children: [
          for (var i = 0; i < sunucu.length; i++) ...[
            if (i > 0) const _Ayirac(),
            _HatSatiri(h: sunucu[i]),
          ],
        ],
      );
    }
    if (yerel != null && !yerel.bos) {
      final kanallar = [
        if (yerel.uygulama) 'Uygulama',
        if (yerel.eposta) 'E-posta',
        if (yerel.sms) 'SMS',
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final dk in yerel.dakikalar)
                Chip(
                  label: Text(hatirlaticiEtiketi(dk)),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(
                    Icons.notifications_none_rounded,
                    size: 16,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$kanallar${_p!.bekleyen ? ' · gönderilince kurulur' : ''}',
            style: tema.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Text(
      ekVar || _p!.no == null
          ? 'Hatırlatıcı yok'
          : 'Bağlantı kurulunca yüklenir',
      style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
    );
  }
}

class _OzetKarti extends StatelessWidget {
  const _OzetKarti({required this.program, required this.durum, this.randevu});

  final Program program;
  final ProgramZamani durum;
  final String? randevu;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final r = program.renk;
    final koyu = acik
        ? Color.lerp(r, Colors.black, 0.35)!
        : Color.lerp(r, Colors.white, 0.45)!;
    final (etiket, ikon, ren) = switch (durum) {
      ProgramZamani.suan => ('ŞİMDİ', Icons.circle, const Color(0xFF12A150)),
      ProgramZamani.gecmis => (
        'Tamamlandı',
        Icons.check_circle_outline_rounded,
        cs.outline,
      ),
      ProgramZamani.gelecek => (
        kalanYazi(program).isEmpty ? 'Yaklaşıyor' : kalanYazi(program),
        Icons.schedule_rounded,
        r,
      ),
    };
    Widget rozet(IconData i, String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 6),
          Text(
            t,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: programGolgesi(context),
        ),
        child: Material(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 6,
                child: ColoredBox(color: r),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
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
                      program.adi,
                      style: tema.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                        height: 1.2,
                        color: koyu,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        rozet(ikon, etiket, ren),
                        rozet(
                          Icons.calendar_today_outlined,
                          program.tumGun
                              ? 'Gün boyu'
                              : '${saatYaz(program.bas)} – ${saatYaz(program.bit)}',
                          cs.primary,
                        ),
                        rozet(
                          Icons.timelapse_rounded,
                          sureYaz(program.bit.difference(program.bas)),
                          cs.onSurfaceVariant,
                        ),
                        if (program.randevuNo > 0)
                          rozet(
                            Icons.handshake_outlined,
                            (randevu ?? '').isEmpty
                                ? 'Randevudan oluşturuldu'
                                : 'Randevu: $randevu',
                            const Color(0xFF636E82),
                          ),
                        if (program.bekleyen)
                          rozet(
                            Icons.cloud_upload_outlined,
                            'Gönderilecek',
                            cs.outline,
                          ),
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

class _EylemSatiri extends StatelessWidget {
  const _EylemSatiri({
    required this.yerVar,
    required this.harita,
    required this.takvim,
  });

  final bool yerVar;
  final VoidCallback harita;
  final VoidCallback takvim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          if (yerVar) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: harita,
                icon: const Icon(Icons.map_outlined, size: 19),
                label: const Text('Haritada aç'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: OutlinedButton.icon(
              onPressed: takvim,
              icon: const Icon(Icons.calendar_month_outlined, size: 19),
              label: const Text('Takvime ekle'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HatSatiri extends StatelessWidget {
  const _HatSatiri({required this.h});

  final Map<String, dynamic> h;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final durum = '${h['durum']}';
    final (yazi, renk, ikon) = switch (durum) {
      'gonderildi' => (
        'Gönderildi',
        const Color(0xFF12A150),
        Icons.check_circle_outline_rounded,
      ),
      'iptal' => ('İptal', cs.outline, Icons.cancel_outlined),
      _ => ('Bekliyor', const Color(0xFFE0A100), Icons.schedule_rounded),
    };
    final z = programZamani(h['zaman']);
    final kanallar = ((h['kanal'] as List?) ?? const []).join(' · ');
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: renk.withValues(alpha: 0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(ikon, size: 19, color: renk),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${h['etiket']}',
                style: tema.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  if (z != null)
                    '${z.day} ${trAylarKisa[z.month]} ${saatYaz(z)}',
                  if (kanallar.isNotEmpty) kanallar,
                  if ((h['ertelendi'] as num?)?.toInt() == 1) 'ertelendi',
                ].join(' · '),
                style: tema.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          yazi,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: renk,
          ),
        ),
      ],
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir(this.ikon, this.etiket, this.deger);

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

class _SayiRozeti extends StatelessWidget {
  const _SayiRozeti(this.sayi);

  final int sayi;

  @override
  Widget build(BuildContext context) {
    if (sayi <= 0) return const SizedBox.shrink();
    final v = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: v.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$sayi',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: v),
      ),
    );
  }
}

class _Bilgi extends StatelessWidget {
  const _Bilgi({required this.metin, this.eylem});

  final String metin;
  final Widget? eylem;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tema.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded),
          const SizedBox(width: 12),
          Expanded(child: Text(metin, style: tema.textTheme.bodyMedium)),
          ?eylem,
        ],
      ),
    );
  }
}

/// Çakışma / gönderim hatası: açıklama ve çözüm düğmeleri.
class _SorunSeridi extends StatelessWidget {
  const _SorunSeridi({
    required this.op,
    required this.depo,
    required this.motor,
  });

  final KuyrukOp op;
  final ProgramDeposu depo;
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
                        ? 'Bu program siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
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
                      await depo.cakismaBenimkiniGonder(op);
                      motor.senkronla();
                    },
                    child: const Text('Benimkini koru'),
                  ),
                  OutlinedButton(
                    onPressed: () => depo.cakismaSunucuyuAl(op),
                    child: const Text('Sunucudakini al'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () => depo.islemiIptalEt(op),
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
