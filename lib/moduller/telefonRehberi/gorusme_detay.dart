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
import 'gorusme_formu.dart';
import 'kisi_detay.dart';
import 'kisi_formu.dart';
import 'rehber_ortak.dart';

/// Görüşme ayrıntısı: kişi ve telefonlar (tek dokunuşla ara), durum ve zaman (takip görüşmesiyle), konu, not,
/// aynı kişiyle önceki görüşmeler, rehber durumu ve kayıt bilgileri.
class GorusmeDetay extends StatefulWidget {
  const GorusmeDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<GorusmeDetay> createState() => _GorusmeDetayState();
}

class _GorusmeDetayState extends State<GorusmeDetay> {
  Gorusme? _g;
  KuyrukOp? _sorun;
  Map<String, dynamic>? _ek;
  RehberReferans _ref = RehberReferans({});
  List<Gorusme> _onceki = [];
  Kisi? _kisi;
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
    final g = await _depo.gorusmeGetir(widget.yerelId);
    final s = (await _depo.sorunlular(RehberVarlik.gorusme))[widget.yerelId];
    final ref = await _depo.referans();
    if (!mounted) return;
    if (g == null || g.silindi) {
      Navigator.of(context).maybePop();
      return;
    }
    final ek = g.no == null ? null : await _depo.ekOku('gorusme${g.no}');
    final onceki = await _depo.oncekiGorusmeler(g);
    final kisi = await _depo.kisiBul(g.adi, g.tel1);
    if (!mounted) return;
    final ilk = !_yuklendi;
    setState(() {
      _g = g;
      _sorun = s;
      _ek = ek;
      _ref = RehberReferans(ref);
      _onceki = onceki;
      _kisi = kisi;
      _yuklendi = true;
    });
    if (ilk) _ekiYenile();
  }

  Future<void> _ekiYenile() async {
    final no = _g?.no;
    final senk = widget.veri.motor.rehberSenkron;
    if (no == null || senk == null) return;
    setState(() {
      _ekYukleniyor = true;
      _ekHata = false;
    });
    try {
      final v = await senk.gorusmeAyrintisi(no);
      if (mounted) setState(() => _ek = v);
    } on ApiHata {
      if (mounted) setState(() => _ekHata = true);
    } finally {
      if (mounted) setState(() => _ekYukleniyor = false);
    }
  }

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GorusmeFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Görüşme silinsin mi?'),
        content: const Text(
          'Kayıt çöp kutusuna taşınır (web panelinden geri alınabilir).',
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
    await _depo.gorusmeSil(widget.yerelId);
    if (mounted) Navigator.of(context).pop();
  }

  String _z(DateTime t) =>
      '${t.day} ${trAylar[t.month]} ${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _kimNe(Object? b) {
    if (b is! Map) return '—';
    final ad = '${b['adi'] ?? ''}'.trim();
    final z = uzunZaman(b['zaman'] as String?);
    final p = [if (ad.isNotEmpty) ad, ?z];
    return p.isEmpty ? '—' : p.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    if (!_yuklendi || g == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final renk1 = gorusmeDurumRengi(g.d1);
    final koyuluk = acik ? Colors.black : Colors.white;

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
            ikon: Icons.phone_in_talk_outlined,
            baslik: 'GÖRÜŞME DETAYI',
            altBaslik: _z(g.t1),
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
                            baslik: 'Kişi / kurum',
                            ikon: Icons.person_outline_rounded,
                            sag: _kisi != null && _kisi!.kara
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
                                  trBuyuk(g.adi),
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                if (g.unvan.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      g.unvan.trim(),
                                      style: tema.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                TelefonSatiri(
                                  etiket: 'Telefon 1',
                                  numara: g.tel1,
                                  dahili: g.dah1,
                                  mesajlasma: true,
                                ),
                                TelefonSatiri(
                                  etiket: 'Telefon 2',
                                  numara: g.tel2,
                                  dahili: g.dah2,
                                  mesajlasma: true,
                                ),
                                const SizedBox(height: 4),
                                if (_kisi != null)
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => KisiDetay(
                                          veri: widget.veri,
                                          yerelId: _kisi!.yerelId!,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.contacts_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Rehber kaydını aç'),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => KisiFormu(
                                          veri: widget.veri,
                                          baslangic: {
                                            'adi': g.adi,
                                            'unvan': g.unvan,
                                            'cep1': g.tel1,
                                            'cep2': g.tel2,
                                          },
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.person_add_alt_1_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Rehbere ekle'),
                                  ),
                              ],
                            ),
                          ),
                          ProgramKutu(
                            baslik: 'Görüşme',
                            ikon: Icons.phone_in_talk_outlined,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _DurumSatiri(
                                  durum: _ref.durumAdi(g.d1),
                                  renk: renk1,
                                  yazi: Color.lerp(renk1, koyuluk, 0.35)!,
                                  ikon: gorusmeDurumIkonu(g.d1),
                                  zaman: _z(g.t1),
                                ),
                                if (g.d2 > 0 && g.t2 != null) ...[
                                  const SizedBox(height: 10),
                                  _DurumSatiri(
                                    durum: 'Takip: ${_ref.durumAdi(g.d2)}',
                                    renk: gorusmeDurumRengi(g.d2),
                                    yazi: Color.lerp(
                                      gorusmeDurumRengi(g.d2),
                                      koyuluk,
                                      0.35,
                                    )!,
                                    ikon: Icons.event_repeat_rounded,
                                    zaman: _z(g.t2!),
                                  ),
                                ],
                                if (g.konu.trim().isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    'Konu',
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    g.konu.trim(),
                                    style: tema.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                                if (g.ulasilamadi &&
                                    g.tel1.trim().isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: () => telefonAra(g.tel1),
                                    icon: const Icon(Icons.call_rounded),
                                    label: const Text('Tekrar ara'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (g.notum.trim().isNotEmpty)
                            ProgramKutu(
                              baslik: 'Notum',
                              ikon: Icons.notes_rounded,
                              cocuk: SelectableText(
                                g.notum.trim(),
                                style: tema.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          if (_onceki.isNotEmpty)
                            ProgramKutu(
                              baslik: 'Önceki görüşmeler',
                              ikon: Icons.history_rounded,
                              sag: Text(
                                '${_onceki.length}',
                                style: tema.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              cocuk: Column(
                                children: [
                                  for (final o in _onceki)
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () =>
                                          Navigator.of(context).pushReplacement(
                                            MaterialPageRoute(
                                              builder: (_) => GorusmeDetay(
                                                veri: widget.veri,
                                                yerelId: o.yerelId!,
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
                                              gorusmeDurumIkonu(o.d1),
                                              size: 18,
                                              color: gorusmeDurumRengi(o.d1),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                o.konu.trim().isEmpty
                                                    ? _ref.durumAdi(o.d1)
                                                    : o.konu.trim(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              '${o.t1.day} ${trAylarKisa[o.t1.month]} ${o.t1.year}',
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
                            cocuk: _ek == null
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
                                      _Satir2(
                                        'Kaydeden',
                                        '${_ek!['ekleyen'] ?? ''}'.isEmpty
                                            ? _ref.kaydedenAdi(g.ekleyen)
                                            : '${_ek!['ekleyen']}',
                                      ),
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

class _DurumSatiri extends StatelessWidget {
  const _DurumSatiri({
    required this.durum,
    required this.renk,
    required this.yazi,
    required this.ikon,
    required this.zaman,
  });

  final String durum;
  final Color renk;
  final Color yazi;
  final IconData ikon;
  final String zaman;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: renk.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: renk.withValues(alpha: 0.4)),
          ),
          child: Icon(ikon, color: yazi, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                durum,
                style: TextStyle(fontWeight: FontWeight.w700, color: yazi),
              ),
              Text(
                zaman,
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
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
                        ? 'Bu görüşme siz çevrimdışıyken başkası tarafından değiştirilmiş. Hangisini tutacağınızı seçin.'
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
                      await depo.cakismaBenimkiniGonder(
                        RehberVarlik.gorusme,
                        op,
                      );
                      motor.senkronla();
                    },
                    child: const Text('Benimkini koru'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        depo.cakismaSunucuyuAl(RehberVarlik.gorusme, op),
                    child: const Text('Sunucudakini al'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: () =>
                        depo.islemiIptalEt(RehberVarlik.gorusme, op),
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
