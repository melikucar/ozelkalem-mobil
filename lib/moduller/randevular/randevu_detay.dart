import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_istemci.dart';
import '../../veri/yazi_formatlari.dart';
import '../../veri/randevu.dart';
import '../../veri/randevu_deposu.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../programlar/program_detay.dart';
import '../programlar/program_ortak.dart';
import 'randevu_formu.dart';
import 'randevu_ortak.dart';

/// Randevu ayrıntısı: kişi ve hızlı iletişim, zaman, yer, durum (tek dokunuşla değişir), takvim bağlantısı, notlar,
/// aynı kişinin diğer randevuları ve kayıt bilgileri.
class RandevuDetay extends StatefulWidget {
  const RandevuDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<RandevuDetay> createState() => _RandevuDetayState();
}

class _RandevuDetayState extends State<RandevuDetay> {
  Randevu? _r;
  KuyrukOp? _sorun;
  Map<String, dynamic>? _ek;
  List<Randevu> _gecmis = [];
  RandevuReferans _ref = RandevuReferans({});
  bool _yuklendi = false;
  bool _ekYukleniyor = false;
  bool _ekHata = false;

  RandevuDeposu get _depo => widget.veri.randevular;

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
    final r = await _depo.getir(widget.yerelId);
    final s = (await _depo.sorunlular())[widget.yerelId];
    final ek = r?.no == null ? null : await _depo.ekOku(r!.no!);
    final ref = await _depo.referans();
    final g = r == null ? <Randevu>[] : await _depo.kisiGecmisi(r);
    if (!mounted) return;
    if (r == null || r.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ilk = !_yuklendi;
    setState(() {
      _r = r;
      _sorun = s;
      _ek = ek;
      _gecmis = g;
      _ref = RandevuReferans(ref);
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _r?.no;
    final senk = widget.veri.motor.randevuSenkron;
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

  void _mesaj(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RandevuFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Randevu silinsin mi?'),
        content: const Text(
          'Randevu, takvimdeki karşılığıyla birlikte çöp kutusuna taşınır (web panelinden geri alınabilir).',
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

  Future<void> _smsAc() async {
    final r = telefonRakamlari(_r!.telefon);
    if (r.isEmpty) return;
    await launchUrl(Uri(scheme: 'sms', path: '+$r'));
  }

  Future<void> _haritadaAc() async {
    final yer = _r?.yer.trim() ?? '';
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

  Future<void> _programiAc() async {
    final no = _r?.programNo ?? 0;
    final id = no > 0 ? await widget.veri.programlar.yerelIdNo(no) : null;
    if (!mounted) return;
    if (id == null) {
      _mesaj('Takvimdeki program henüz cihaza inmedi; eşitlenince açılır.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgramDetay(veri: widget.veri, yerelId: id),
      ),
    );
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
    final r = _r;
    if (!_yuklendi || r == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final renk = _ref.durumRengi(r.durum);
    final goreli = randevuGoreli(r.bas);
    final ek = _ek;
    final tel = telefonRakamlari(r.telefon);
    final kat = _ref.kategoriAdi(r.katno);

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
            ikon: Icons.event_available_outlined,
            baslik: 'RANDEVU DETAYI',
            altBaslik: uzunGunYaz(r.bas),
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
                          ProgramKutu(
                            baslik: 'İlgili kişi / kurum',
                            ikon: Icons.person_outline_rounded,
                            sag: DurumRozeti(
                              ad: _ref.durumAdi(r.durum),
                              renk: renk,
                            ),
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trBuyuk(r.adi),
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (r.unvan.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      trBuyuk(r.unvan),
                                      style: tema.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                if (tel.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r.telefon,
                                          style: tema.textTheme.bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      _IletisimDugmesi(
                                        ikon: Icons.call_rounded,
                                        renk: const Color(0xFF16A34A),
                                        ipucu: 'Ara',
                                        tikla: () => randevuAra(r.telefon),
                                      ),
                                      const SizedBox(width: 8),
                                      _IletisimDugmesi(
                                        ikon: Icons.chat_rounded,
                                        renk: const Color(0xFF0E9F6E),
                                        ipucu: 'WhatsApp',
                                        tikla: () => randevuWhatsapp(r.telefon),
                                      ),
                                      const SizedBox(width: 8),
                                      _IletisimDugmesi(
                                        ikon: Icons.sms_outlined,
                                        renk: cs.primary,
                                        ipucu: 'SMS',
                                        tikla: _smsAc,
                                      ),
                                    ],
                                  ),
                                ],
                                if (ek != null &&
                                    (ek['rehberde'] == true ||
                                        ek['kara_liste'] == true)) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      if (ek['rehberde'] == true)
                                        const _Etiket(
                                          ikon: Icons.contacts_outlined,
                                          metin: 'Rehberde kayıtlı',
                                        ),
                                      if (ek['kara_liste'] == true)
                                        const _Etiket(
                                          ikon: Icons.block_rounded,
                                          metin: 'Kara listede',
                                          renk: Color(0xFFE11D48),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Zaman ve yer',
                            ikon: Icons.schedule_rounded,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    TarihYapragi(tarih: r.bas, renk: renk),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${saatYaz(r.bas)} – ${saatYaz(r.bit)}',
                                            style: tema.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${uzunGunYaz(r.bas)} · ${_ref.sureEtiketi(r.sureDk)}',
                                            style: tema.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (goreli.etiket.isNotEmpty)
                                      Text(
                                        goreli.etiket,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: goreliRenk(
                                            context,
                                            goreli.ton,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (r.yer.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _haritadaAc,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.place_outlined,
                                            size: 20,
                                            color: cs.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(r.yer)),
                                          Icon(
                                            Icons.map_outlined,
                                            size: 18,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Durum',
                            ikon: Icons.flag_outlined,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (kat.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      kat,
                                      style: tema.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: DurumRozeti(
                                    ad: _ref.durumAdi(r.durum),
                                    renk: renk,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (r.programNo > 0)
                                  _TakvimBagi(
                                    metin:
                                        (ek?['program_adi'] as String?) ??
                                        'Takvime işlendi',
                                    tikla: _programiAc,
                                  )
                                else
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.event_busy_outlined,
                                        size: 18,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _ref.takvimeAlinir(r.durum)
                                              ? 'Eşitlenince takvime işlenecek.'
                                              : 'Takvime işlenmedi. Durum “Randevu Verildi” olunca otomatik eklenir.',
                                          style: tema.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          if (r.notlar.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Notlar',
                              ikon: Icons.notes_rounded,
                              cocuk: SelectableText(
                                r.notlar,
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  height: 1.45,
                                ),
                              ),
                            ),
                          if (_gecmis.isNotEmpty)
                            ProgramKutu(
                              baslik: 'Aynı kişinin diğer randevuları',
                              ikon: Icons.history_rounded,
                              cocuk: Column(
                                children: [
                                  for (final g in _gecmis)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () =>
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder: (_) => RandevuDetay(
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
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _ref.durumRengi(g.durum),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '${g.bas.day} ${trAylarKisa[g.bas.month]} ${g.bas.year} · ${saatYaz(g.bas)}',
                                              ),
                                            ),
                                            Text(
                                              _ref.durumAdi(g.durum),
                                              style: tema.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ProgramKutu(
                            baslik: 'Kayıt bilgileri',
                            ikon: Icons.info_outline_rounded,
                            cocuk: ek == null
                                ? Text(
                                    _ekHata
                                        ? 'Kaydeden ve kayıt zamanları için bağlantı gerekir.'
                                        : 'Yükleniyor…',
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  )
                                : Column(
                                    children: [
                                      _Satir(
                                        'Kaydeden',
                                        '${ek['ekleyen'] ?? ''}'.isEmpty
                                            ? '—'
                                            : '${ek['ekleyen']}',
                                      ),
                                      _Satir(
                                        'İlk kayıt',
                                        _kimNe(ek['ilk_kayit']),
                                      ),
                                      _Satir(
                                        'Son güncelleme',
                                        _kimNe(ek['son_guncelleme']),
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

class _IletisimDugmesi extends StatelessWidget {
  const _IletisimDugmesi({
    required this.ikon,
    required this.renk,
    required this.ipucu,
    required this.tikla,
  });

  final IconData ikon;
  final Color renk;
  final String ipucu;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: ipucu,
    child: Material(
      color: renk.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: tikla,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(ikon, size: 20, color: renk),
        ),
      ),
    ),
  );
}

class _Etiket extends StatelessWidget {
  const _Etiket({required this.ikon, required this.metin, this.renk});

  final IconData ikon;
  final String metin;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final c = renk ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            metin,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _TakvimBagi extends StatelessWidget {
  const _TakvimBagi({required this.metin, required this.tikla});

  final String metin;
  final VoidCallback tikla;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: tikla,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.event_available_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Takvimde: $metin',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _Satir extends StatelessWidget {
  const _Satir(this.etiket, this.deger);

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
          Expanded(child: Text(deger, style: tema.textTheme.bodyMedium)),
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
  final RandevuDeposu depo;
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
                        ? 'Bu randevu siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
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
