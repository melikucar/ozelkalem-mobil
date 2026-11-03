import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/oturum.dart';
import 'bildirim/bildirim_servisi.dart';
import 'bildirim/bildirim_toast.dart';
import 'api/token_deposu.dart';
import 'diger/acilis_ekrani.dart';
import 'diger/kabuk.dart';
import 'diger/esnemesiz_kaydirma.dart';
import 'diger/durum_ekranlari.dart';
import 'diger/giris_ekrani.dart';
import 'tema/tema.dart';
import 'veri/veri_katmani.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final oturum = Oturum(TokenDeposu())..baslat();
  runApp(OzelKalemUygulamasi(oturum: oturum));
  // Bildirim izni uygulama ilk açıldığında istenir
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => BildirimServisi.ornek.baslat(),
  );
}

class OzelKalemUygulamasi extends StatefulWidget {
  const OzelKalemUygulamasi({
    super.key,
    required this.oturum,
    this.acilisSuresi = const Duration(milliseconds: 2600),
  });

  final Oturum oturum;

  /// Oturum kontrolü daha önce bitse bile açılış ekranının en az bu kadar görünmesi (animasyon tamamlansın).
  final Duration acilisSuresi;

  @override
  State<OzelKalemUygulamasi> createState() => _OzelKalemUygulamasiState();
}

class _OzelKalemUygulamasiState extends State<OzelKalemUygulamasi> {
  late bool _acilis = widget.acilisSuresi > Duration.zero;
  Timer? _zamanlayici;

  Oturum get oturum => widget.oturum;

  @override
  void initState() {
    super.initState();
    if (_acilis) {
      _zamanlayici = Timer(widget.acilisSuresi, () {
        if (mounted) setState(() => _acilis = false);
      });
    }
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Giriş öncesi marka teması (lacivert + altın); girişten sonra kullanıcının kendi tercihi (stil × mod × renk)
    return ListenableBuilder(
      listenable: oturum,
      builder: (context, _) {
        final acik = oturum.durum == OturumDurumu.acik;
        final tercih = oturum.tema;
        return MaterialApp(
          title: 'Özel Kalem Otomasyonu',
          scrollBehavior: const EsnemesizKaydirma(),
          debugShowCheckedModeBanner: false,
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: acik ? temaUret(tercih) : girisTemasi(),
          builder: (context, child) => BildirimToast(
            child: (acik && tercih.stil == 'cam')
                ? DecoratedBox(decoration: camZemin(tercih), child: child!)
                : (child ?? const SizedBox.shrink()),
          ),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOut,
            child: KeyedSubtree(
              key: ValueKey(
                _acilis || oturum.durum == OturumDurumu.basliyor
                    ? 'acilis'
                    : oturum.durum,
              ),
              child: _acilis
                  ? const AcilisEkrani()
                  : switch (oturum.durum) {
                      OturumDurumu.basliyor => const AcilisEkrani(),
                      OturumDurumu.girisGerekli => GirisEkrani(oturum: oturum),
                      OturumDurumu.acik => AcikOturum(oturum: oturum),
                      OturumDurumu.baglantiYok => BaglantiYokEkrani(
                        oturum: oturum,
                      ),
                      OturumDurumu.guncellemeZorunlu => GuncellemeEkrani(
                        oturum: oturum,
                      ),
                    },
            ),
          ),
        );
      },
    );
  }
}

/// Oturum açıkken: kullanıcının yerel veritabanını ve senkron motorunu açar, kapanınca durdurur.
class AcikOturum extends StatefulWidget {
  const AcikOturum({super.key, required this.oturum});

  final Oturum oturum;

  @override
  State<AcikOturum> createState() => _AcikOturumState();
}

class _AcikOturumState extends State<AcikOturum> {
  VeriKatmani? _veri;
  Object? _hata;

  @override
  void initState() {
    super.initState();
    VeriKatmani.ac(widget.oturum)
        .then((v) {
          if (!mounted) {
            v.kapat();
            return;
          }
          setState(() => _veri = v);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _hata = e);
        });
  }

  @override
  void dispose() {
    _veri?.kapat(); // oturum 401 ile düştüyse veriler (ve bekleyen değişiklikler) cihazda kalır; yeniden girişte sürer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hata != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Yerel veritabanı açılamadı: $_hata'),
          ),
        ),
      );
    }
    final v = _veri;
    if (v == null) return const AcilisEkrani(animasyonlu: false);
    return AnaKabuk(oturum: widget.oturum, veri: v);
  }
}
