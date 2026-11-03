import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_istemci.dart';
import '../api/oturum.dart';
import '../tema/tema.dart';
import '../veri/yazi_formatlari.dart';
import '../veri/veri_katmani.dart';
import 'ana_sayfa.dart' show hesaptanCik;
import 'hakkinda_sayfasi.dart';
import 'dosya_islemleri.dart';
import '../diger/modul_hero.dart';
import '../diger/tema_secici.dart';

/// Profilim (web "Profilim" karşılığı): profil fotoğrafı, ad, telefon ve şifre güncellenir; T.C. kimlik no yalnızca gösterilir.
/// Görünüm (tema) ve çıkış da buradan yapılır. Düzenleme için bağlantı gerekir (hesap bilgisi anlık sunucuya yazılır).
class ProfilEkrani extends StatefulWidget {
  const ProfilEkrani({
    super.key,
    required this.oturum,
    required this.veri,
    this.sekme = false,
  });

  final Oturum oturum;
  final VeriKatmani veri;

  /// Alt çubuktaki Profil sekmesi olarak açıldıysa geri oku gösterilmez.
  final bool sekme;

  @override
  State<ProfilEkrani> createState() => _ProfilEkraniState();
}

class _ProfilEkraniState extends State<ProfilEkrani> {
  final _form = GlobalKey<FormState>();
  final _ad = TextEditingController();
  final _telefon = TextEditingController();
  final _mevcut = TextEditingController();
  final _yeni = TextEditingController();
  final _tekrar = TextEditingController();

  String _tckn = '';
  bool _yuklendi = false;
  bool _yukleniyor = false;
  bool _fotoYukleniyor = false;
  bool _sifreGizli = true;
  String? _hata;
  String? _basari;

  Oturum get oturum => widget.oturum;

  @override
  void initState() {
    super.initState();
    final y = (oturum.ben?['yonetici'] as Map?) ?? const {};
    _ad.text = (y['adi'] ?? '').toString();
    _getir();
  }

  @override
  void dispose() {
    for (final c in [_ad, _telefon, _mevcut, _yeni, _tekrar]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _getir() async {
    try {
      final v = await oturum.api.get('profil');
      if (!mounted) return;
      setState(() {
        _ad.text = (v['adi'] ?? '').toString();
        _telefon.text = (v['telefon'] ?? '').toString();
        _tckn = (v['tckn'] ?? '').toString();
        _yuklendi = true;
        _hata = null;
      });
    } on ApiHata catch (e) {
      if (mounted) {
        setState(
          () => _hata = e.agHatasi
              ? 'Profil bilgilerini görmek ve değiştirmek için internet bağlantısı gerekir.'
              : e.mesaj,
        );
      }
    }
  }

  Future<void> _kaydet() async {
    if (_yukleniyor || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _yukleniyor = true;
      _hata = null;
      _basari = null;
    });
    try {
      final sifre = _yeni.text;
      final v = await oturum.api.post(
        'profil/kaydet',
        govde: {
          'adi': _ad.text.trim(),
          'telefon': _telefon.text.trim(),
          if (sifre.isNotEmpty) 'sifre': sifre,
          if (sifre.isNotEmpty) 'mevcut_sifre': _mevcut.text,
        },
      );
      await oturum.benYukle(); // ad ve fotoğraf özeti tazelenir
      if (!mounted) return;
      setState(() {
        _basari = v['sifre_degisti'] == true
            ? 'Profiliniz ve şifreniz güncellendi. Diğer cihazlardaki oturumlar kapatıldı.'
            : 'Profiliniz güncellendi.';
        _mevcut.clear();
        _yeni.clear();
        _tekrar.clear();
      });
    } on ApiHata catch (e) {
      if (mounted) {
        setState(
          () => _hata = e.agHatasi
              ? 'İnternet bağlantısı yok; profil değişikliği kaydedilemedi.'
              : e.mesaj,
        );
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _fotoSec() async {
    final kaynak = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(c, 'kamera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(c, 'galeri'),
            ),
          ],
        ),
      ),
    );
    if (kaynak == null) return;
    try {
      final l = kaynak == 'kamera' ? await fotografCek() : await galeridenSec();
      if (l.isEmpty) return;
      setState(() {
        _fotoYukleniyor = true;
        _hata = null;
        _basari = null;
      });
      final d = l.first;
      await oturum.api.yukle(
        'profil/foto-yukle',
        alanlar: const {},
        dosyaAlani: 'dosya',
        dosyaYolu: d.yol,
        dosyaAdi: d.ad,
      );
      try {
        File(d.yol).deleteSync();
      } catch (_) {}
      await oturum.benYukle();
      if (mounted) setState(() => _basari = 'Profil fotoğrafı güncellendi.');
    } on ApiHata catch (e) {
      if (mounted) {
        setState(
          () => _hata = e.agHatasi
              ? 'İnternet bağlantısı yok; fotoğraf yüklenemedi.'
              : e.mesaj,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _hata =
              'Fotoğraf alınamadı. İzinleri kontrol edip tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _fotoYukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(
      zemin,
      tema.colorScheme.primary,
      acik ? 0.10 : 0.14,
    )!;
    final makam = (oturum.ben?['makam'] as Map?) ?? const {};

    InputDecoration dekor(String e, IconData i) =>
        InputDecoration(labelText: e, prefixIcon: Icon(i));

    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: !widget.sekme,
            ikon: Icons.person_outline_rounded,
            baslik: 'Profilim',
            altBaslik: 'Hesap bilgilerinizi güncelleyin',
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
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: GestureDetector(
                                onTap: _fotoYukleniyor ? null : _fotoSec,
                                child: Stack(
                                  children: [
                                    _Avatar(foto: oturum.profilFoto),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: tema.colorScheme.primary,
                                          border: Border.all(
                                            color: tema.colorScheme.surface,
                                            width: 2,
                                          ),
                                        ),
                                        child: _fotoYukleniyor
                                            ? const Padding(
                                                padding: EdgeInsets.all(8),
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.photo_camera_rounded,
                                                size: 17,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              trBuyuk(_ad.text),
                              textAlign: TextAlign.center,
                              style: tema.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ('${makam['adi'] ?? ''}'.isNotEmpty)
                              Text(
                                '${makam['adi']}',
                                textAlign: TextAlign.center,
                                style: tema.textTheme.bodySmall?.copyWith(
                                  color: tema.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: 18),
                            _Kutu(
                              baslik: 'Hesap bilgileri',
                              ikon: Icons.badge_outlined,
                              cocuk: Column(
                                children: [
                                  if (_tckn.isNotEmpty)
                                    InputDecorator(
                                      decoration: dekor(
                                        'T.C. kimlik no (değiştirilemez)',
                                        Icons.lock_outline,
                                      ),
                                      child: Text(_tckn),
                                    ),
                                  if (_tckn.isNotEmpty)
                                    const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _ad,
                                    enabled: _yuklendi && !_yukleniyor,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: dekor(
                                      'Ad soyad',
                                      Icons.person_outline,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                        ? 'Adınızı girin'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _telefon,
                                    enabled: _yuklendi && !_yukleniyor,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9 ()+-]'),
                                      ),
                                    ],
                                    decoration: dekor(
                                      'Cep telefonu',
                                      Icons.phone_iphone_rounded,
                                    ),
                                    validator: (v) =>
                                        (v == null ||
                                            v
                                                    .replaceAll(
                                                      RegExp(r'\D'),
                                                      '',
                                                    )
                                                    .length <
                                                10)
                                        ? 'Cep telefonunuzu girin'
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            _Kutu(
                              baslik: 'Şifre değiştir',
                              ikon: Icons.lock_reset_rounded,
                              cocuk: Column(
                                children: [
                                  Text(
                                    'Şifrenizi değiştirmek istemiyorsanız bu bölümü boş bırakın.',
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: tema.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _mevcut,
                                    enabled: _yuklendi && !_yukleniyor,
                                    obscureText: _sifreGizli,
                                    decoration: dekor(
                                      'Mevcut şifre',
                                      Icons.key_outlined,
                                    ),
                                    validator: (v) =>
                                        (_yeni.text.isNotEmpty &&
                                            (v == null || v.isEmpty))
                                        ? 'Mevcut şifrenizi girin'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _yeni,
                                    enabled: _yuklendi && !_yukleniyor,
                                    obscureText: _sifreGizli,
                                    decoration:
                                        dekor(
                                          'Yeni şifre',
                                          Icons.lock_outline,
                                        ).copyWith(
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _sifreGizli
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                            onPressed: () => setState(
                                              () => _sifreGizli = !_sifreGizli,
                                            ),
                                          ),
                                        ),
                                    validator: (v) =>
                                        (v != null &&
                                            v.isNotEmpty &&
                                            v.length < 6)
                                        ? 'Şifre en az 6 karakter olmalı'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _tekrar,
                                    enabled: _yuklendi && !_yukleniyor,
                                    obscureText: _sifreGizli,
                                    decoration: dekor(
                                      'Yeni şifre (tekrar)',
                                      Icons.lock_outline,
                                    ),
                                    validator: (v) => v != _yeni.text
                                        ? 'Şifreler aynı değil'
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            if (_hata != null)
                              _Mesaj(hata: true, metin: _hata!),
                            if (_basari != null)
                              _Mesaj(hata: false, metin: _basari!),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: (_yuklendi && !_yukleniyor)
                                    ? _kaydet
                                    : null,
                                icon: _yukleniyor
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: const Text('Değişiklikleri kaydet'),
                              ),
                            ),
                            if (!_yuklendi && _hata != null)
                              TextButton(
                                onPressed: _getir,
                                child: const Text('Yeniden dene'),
                              ),
                            const SizedBox(height: 22),
                            OutlinedButton.icon(
                              onPressed: () => temaSeciciAc(context, oturum),
                              icon: const Icon(Icons.palette_outlined),
                              label: const Text('Görünüm'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      HakkindaSayfasi(surum: oturum.surum),
                                ),
                              ),
                              icon: const Icon(Icons.info_outline_rounded),
                              label: const Text('Uygulama Hakkında'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  hesaptanCik(context, oturum, widget.veri),
                              icon: Icon(
                                Icons.logout,
                                color: tema.colorScheme.error,
                              ),
                              label: Text(
                                'Çıkış yap',
                                style: TextStyle(color: tema.colorScheme.error),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                side: BorderSide(
                                  color: tema.colorScheme.error.withValues(
                                    alpha: 0.5,
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.foto});

  final Uint8List? foto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Marka.altin, Marka.altinKoyu]),
      ),
      child: ClipOval(
        child: foto == null
            ? ColoredBox(
                color: tema.colorScheme.surface,
                child: Icon(
                  Icons.person_rounded,
                  size: 54,
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              )
            : Image.memory(
                foto!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
      ),
    );
  }
}

class _Kutu extends StatelessWidget {
  const _Kutu({required this.baslik, required this.ikon, required this.cocuk});

  final String baslik;
  final IconData ikon;
  final Widget cocuk;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final acik = tema.brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (acik ? Marka.lacivert : Colors.black).withValues(
                alpha: acik ? 0.08 : 0.35,
              ),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: tema.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: tema.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        ikon,
                        size: 18,
                        color: tema.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      trBuyuk(baslik),
                      style: tema.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                cocuk,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mesaj extends StatelessWidget {
  const _Mesaj({required this.hata, required this.metin});

  final bool hata;
  final String metin;

  @override
  Widget build(BuildContext context) {
    final renk = hata ? const Color(0xFFB42318) : const Color(0xFF067647);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: renk.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hata ? Icons.error_outline : Icons.check_circle_outline,
              size: 20,
              color: renk,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(metin, style: TextStyle(color: renk, height: 1.35)),
            ),
          ],
        ),
      ),
    );
  }
}
