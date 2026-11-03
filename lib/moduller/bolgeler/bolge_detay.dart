import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../diger/kompakt_dugme.dart';
import '../../diger/modul_hero.dart';
import '../../veri/bolge.dart';
import '../../veri/bolge_deposu.dart';
import '../../veri/talep_deposu.dart' show KuyrukOp;
import '../../veri/tarih_yardimci.dart';
import '../../veri/veri_katmani.dart';
import '../programlar/program_ortak.dart';
import 'bolge_formu.dart';
import 'bolge_ortak.dart';

/// Bölge künyesi: konum, doluluk, muhtar (arama düğmeli) ve bölümlere ayrılmış bilgiler (dolu olanlar görünür).
class BolgeDetay extends StatefulWidget {
  const BolgeDetay({super.key, required this.veri, required this.yerelId});

  final VeriKatmani veri;
  final int yerelId;

  @override
  State<BolgeDetay> createState() => _BolgeDetayState();
}

class _BolgeDetayState extends State<BolgeDetay> {
  Bolge? _b;
  KuyrukOp? _sorun;
  BolgeReferans _ref = BolgeReferans({});
  bool _yuklendi = false;

  BolgeDeposu get _depo => widget.veri.bolgeler;

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
    final b = await _depo.getir(widget.yerelId);
    final s = (await _depo.sorunlular())[widget.yerelId];
    final ref = await _depo.referans();
    if (!mounted) return;
    if (b == null || (b.v['silindi'] as int?) == 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _b = b;
      _sorun = s;
      _ref = BolgeReferans(ref);
      _yuklendi = true;
    });
  }

  Future<void> _duzenle() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BolgeFormu(veri: widget.veri, yerelId: widget.yerelId),
    ),
  );

  Future<void> _sil() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bölge silinsin mi?'),
        content: const Text(
          'Kayıt ve ekleri çöp kutusuna taşınır (web panelinden geri alınabilir).',
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

  Future<void> _ara(String tel) async {
    final temiz = tel.replaceAll(RegExp(r'[^0-9+]'), '');
    if (temiz.isEmpty) return;
    await launchUrl(Uri.parse('tel:$temiz')).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    if (!_yuklendi || b == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    final bilgi = b.bilgi;
    final kaydeden = _ref.kaydedenAdi(b.ekleyen);

    Widget satir(BolgeAlani a, String d) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: a.coklu
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.etiket,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  d,
                  style: tema.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    a.etiket,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: SelectableText(
                    d,
                    textAlign: TextAlign.right,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
    );

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
            ikon: Icons.holiday_village_outlined,
            baslik: b.baslik,
            altBaslik: b.konum.isEmpty ? 'Bölge künyesi' : b.konum,
            eylemler: [
              PopupMenuButton<String>(
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'duzenle') _duzenle();
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
                            baslik: 'Bölge',
                            ikon: Icons.place_outlined,
                            cocuk: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.baslik,
                                  style: tema.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if (b.ilceAdi.isNotEmpty)
                                      BolgeRozet(
                                        metin: b.ilceAdi,
                                        ikon: Icons.map_outlined,
                                      ),
                                    if (b.semtAdi.isNotEmpty)
                                      BolgeRozet(
                                        metin: b.semtAdi,
                                        ikon: Icons.signpost_outlined,
                                      ),
                                    if (kaydeden.isNotEmpty)
                                      BolgeRozet(
                                        metin: kaydeden,
                                        ikon: Icons.edit_outlined,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Bilgi doluluğu',
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DolulukCubugu(deger: b.doluluk),
                                const SizedBox(height: 10),
                                Text(
                                  'Kayıt: ${uzunZaman(b.v['tarih'] as String?) ?? '—'}',
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final bolum in bolgeBolumleri) ...[
                            Builder(
                              builder: (_) {
                                final dolu = [
                                  for (final a in bolum.alanlar)
                                    if ((bilgi[a.anahtar] ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      a,
                                ];
                                if (dolu.isEmpty)
                                  return const SizedBox.shrink();
                                final muhtarBolumu =
                                    bolum.alanlar.first.anahtar == 'muhtar_adi';
                                return ProgramKutu(
                                  baslik: bolum.ad,
                                  ikon: bolum.ikon,
                                  sag:
                                      muhtarBolumu && b.muhtarTelefon.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'Muhtarı ara',
                                          icon: Icon(
                                            Icons.call_rounded,
                                            color: cs.primary,
                                          ),
                                          onPressed: () =>
                                              _ara(b.muhtarTelefon),
                                        )
                                      : null,
                                  cocuk: Column(
                                    children: [
                                      for (final a in dolu)
                                        satir(a, bilgi[a.anahtar]!),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
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

class _SorunSeridi extends StatelessWidget {
  const _SorunSeridi({
    required this.op,
    required this.depo,
    required this.motor,
  });

  final KuyrukOp op;
  final BolgeDeposu depo;
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
