import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/oturum.dart';
import '../bildirim/bildirim_servisi.dart';
import '../veri/veri_katmani.dart';
import '../diger/ana_sayfa.dart';
import 'profil_ekrani.dart';
import 'hakkinda_sayfasi.dart';
import 'hesap_acilir.dart';
import '../diger/modul_hero.dart';
import '../diger/premium_gezinti.dart';
import '../moduller/programlar/programlar_sayfasi.dart';
import '../moduller/randevular/randevular_sayfasi.dart';
import '../moduller/faaliyetler/faaliyetler_sayfasi.dart';
import '../moduller/telefonRehberi/rehber_sayfasi.dart';
import '../moduller/talepler/talepler_listesi.dart';
import '../moduller/yazismalar/yazismalar_sayfasi.dart';
import '../moduller/tbmm/tbmm_sayfasi.dart';
import '../moduller/bolgeler/bolge_sayfasi.dart';
import '../moduller/bakanliklar/bakanlik_sayfasi.dart';
import '../moduller/raporlar/raporlar_sayfasi.dart';

class _Sekme {
  const _Sekme(this.anahtar, this.ad, this.ikon, this.seciliIkon, {this.modul});

  /// Sayfanın kimliği; çoğu sekmede sunucudaki modül adıyla (yoneticiler.moduller, normalleştirilmiş) aynıdır. null = ana sayfa (herkese açık).
  final String? anahtar;

  /// Yetki için bakılan modül, sayfa kimliğinden farklıysa (ör. Randevular, Ajanda modülüne bağlıdır).
  final String? modul;

  String? get izinModulu => modul ?? anahtar;
  final String ad;
  final IconData ikon;
  final IconData seciliIkon;
}

/// Yeni modül eklemek: buraya bir satır + `_sayfa` içinde sayfasını bağlamak yeter. Yetkisi olmayan kullanıcıda sekme görünmez.
const _tumSekmeler = [
  _Sekme(null, 'Ana sayfa', Icons.home_outlined, Icons.home_rounded),
  _Sekme('talepler', 'Talepler', Icons.assignment_outlined, Icons.assignment),
  _Sekme('ajanda', 'Programlar', Icons.event_outlined, Icons.event),
  _Sekme(
    'randevular',
    'Randevular',
    Icons.event_available_outlined,
    Icons.event_available,
    modul: 'ajanda',
  ),
  _Sekme('faaliyetler', 'Faaliyetler', Icons.campaign_outlined, Icons.campaign),
  _Sekme('telefonlar', 'Rehber', Icons.contacts_outlined, Icons.contacts),
  _Sekme('yazismalar', 'Yazışmalar', Icons.mail_outline, Icons.mail),
  _Sekme(
    'raporlar',
    'Raporlar',
    Icons.insert_chart_outlined,
    Icons.insert_chart,
  ),
  _Sekme(
    'tbmm',
    'Yasama',
    Icons.account_balance_outlined,
    Icons.account_balance,
  ),
  _Sekme(
    'bolgeler',
    'Bölgeler',
    Icons.holiday_village_outlined,
    Icons.holiday_village,
  ),
  _Sekme(
    'bakanlikteskilatlari',
    'Bakanlıklar',
    Icons.corporate_fare_outlined,
    Icons.corporate_fare,
  ),
];

/// Oturum açıkken uygulamanın iskeleti: altta kaydırılabilir premium gezinti. Yalnızca kullanıcının yetkili olduğu modüller görünür.
class AnaKabuk extends StatefulWidget {
  const AnaKabuk({super.key, required this.oturum, required this.veri});

  final Oturum oturum;
  final VeriKatmani veri;

  @override
  State<AnaKabuk> createState() => _AnaKabukState();
}

class _AnaKabukState extends State<AnaKabuk> {
  int _secili = 0;

  /// Ana sayfadaki durum bloğundan gelen süzme isteği; Talepler listesi alır ve sıfırlar.
  final _durumIstegi = ValueNotifier<int?>(null);
  int _goruntulenenMesaj = 0;

  @override
  void initState() {
    super.initState();
    widget.veri.motor.addListener(_motorDegisti);
  }

  @override
  void dispose() {
    widget.veri.motor.removeListener(_motorDegisti);
    _durumIstegi.dispose();
    super.dispose();
  }

  /// Gönderim sonuçları (SMS gönderildi mi, rehbere eklendi mi) kısa bir bildirimle gösterilir.
  void _motorDegisti() {
    final m = widget.veri.motor;
    if (m.mesajNo != _goruntulenenMesaj && m.sonMesaj != null) {
      _goruntulenenMesaj = m.mesajNo;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(m.sonMesaj!),
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  final _sayfalar =
      <String, Widget>{}; // sekme sayfaları ilk açılışta kurulur, sonra korunur

  List<_Sekme> get _sekmeler => [
    for (final s in _tumSekmeler)
      if (s.izinModulu == null || widget.oturum.modulVar(s.izinModulu!)) s,
  ];

  void _git(String modul) {
    final i = _sekmeler.indexWhere((s) => s.anahtar == modul);
    if (i >= 0) setState(() => _secili = i);
  }

  Widget _sayfa(_Sekme s) => _sayfalar.putIfAbsent(s.anahtar ?? 'ana', () {
    switch (s.anahtar) {
      case null:
        return AnaSayfa(
          oturum: widget.oturum,
          veri: widget.veri,
          git: _git,
          profilAc: (k) => _hesapAc(k, asagi: true),
          durumGit: (no) {
            _durumIstegi.value = no;
            _git('talepler');
          },
        );
      case 'ajanda':
        return ProgramlarSayfasi(veri: widget.veri, sekme: true);
      case 'telefonlar':
        return RehberSayfasi(veri: widget.veri, sekme: true);
      case 'faaliyetler':
        return FaaliyetlerSayfasi(veri: widget.veri, sekme: true);
      case 'randevular':
        return RandevularSayfasi(veri: widget.veri, sekme: true);
      case 'yazismalar':
        return YazismalarSayfasi(
          veri: widget.veri,
          oturum: widget.oturum,
          sekme: true,
        );
      case 'talepler':
        return TaleplerListesi(
          veri: widget.veri,
          sekme: true,
          durumIstegi: _durumIstegi,
        );
      case 'tbmm':
        return TbmmSayfasi(veri: widget.veri, sekme: true);
      case 'bolgeler':
        return BolgeSayfasi(veri: widget.veri, sekme: true);
      case 'bakanlikteskilatlari':
        return BakanlikSayfasi(veri: widget.veri, sekme: true);
      case 'raporlar':
        return RaporlarSayfasi(oturum: widget.oturum);
      default:
        return YakindaSayfasi(ad: s.ad, ikon: s.seciliIkon);
    }
  });

  /// Hesap menüsü (tema, Profilim, Uygulama Hakkında, çıkış): alt çubuktaki profilden yukarı, ana sayfadaki küçük profilden aşağı açılır.
  Future<void> _hesapAc(Rect kaynak, {bool asagi = false}) => hesapAcilirAc(
    context,
    oturum: widget.oturum,
    kaynak: kaynak,
    asagi: asagi,
    profilim: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilEkrani(oturum: widget.oturum, veri: widget.veri),
      ),
    ),
    hakkinda: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HakkindaSayfasi(surum: widget.oturum.surum),
      ),
    ),
    cikis: () => hesaptanCik(context, widget.oturum, widget.veri),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.oturum,
      builder: (context, _) {
        final sekmeler = _sekmeler;
        final i = _secili < sekmeler.length ? _secili : 0;
        return PopScope(
          canPop: i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              setState(() => _secili = 0); // geri tuşu önce ana sayfaya döner
            }
          },
          child: Scaffold(
            extendBody: true,
            body: GecisliSayfalar(
              index: i,
              children: [
                for (var x = 0; x < sekmeler.length; x++)
                  x == i || _sayfalar.containsKey(sekmeler[x].anahtar ?? 'ana')
                      ? _sayfa(sekmeler[x])
                      : const SizedBox.shrink(),
              ],
            ),
            bottomNavigationBar: PremiumGezinti(
              ogeler: [
                for (final s in sekmeler)
                  GezintiOgesi(s.ad, s.ikon, s.seciliIkon),
              ],
              secili: i,
              sec: (x) => setState(() => _secili = x),
              stil: widget.oturum.tema.stil,
              panelEylemleri: [
                GezintiEylemi(
                  ad: 'Bildirimler',
                  ikon: Icons.notifications_none_rounded,
                  tikla: (_) async {
                    // izin yoksa ister; sonra örnek bir bildirim gösterir (bildirim merkezi sonraki sürümde)
                    await BildirimServisi.ornek.izinIste();
                    BildirimServisi.ornek.goster(
                      'Bildirimler açık',
                      'Yeni gelişmeler burada ve cihaz bildirimi olarak görünecek.',
                    );
                  },
                ),
              ],
              eylemler: [
                GezintiEylemi(
                  ad: 'Profil',
                  ikon: Icons.account_circle_outlined,
                  ozel: (c) => _ProfilRozeti(foto: widget.oturum.profilFoto),
                  tikla: (kaynak) => _hesapAc(kaynak),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Henüz yazılmamış modüller için: ne olduğunu ve şimdilik nereden kullanılacağını söyler.
class YakindaSayfasi extends StatelessWidget {
  const YakindaSayfasi({super.key, required this.ad, required this.ikon});

  final String ad;
  final IconData ikon;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          ModulHero(baslik: ad, altBaslik: 'Yakında', ikon: ikon),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: tema.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          ikon,
                          size: 40,
                          color: tema.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '$ad yakında',
                        style: tema.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bu modül mobil uygulamaya sonraki sürümlerde eklenecek. Şimdilik web panelinden kullanabilirsiniz.',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: tema.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// Dock'taki profil düğmesi: fotoğraf altın halkalı yuvarlak; yoksa hesap simgesi.
class _ProfilRozeti extends StatelessWidget {
  const _ProfilRozeti({required this.foto});

  final Uint8List? foto;

  @override
  Widget build(BuildContext context) {
    if (foto == null) {
      return Icon(
        Icons.account_circle_outlined,
        size: 26,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return SizedBox.expand(
      child: Image.memory(
        foto!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person, color: Colors.white, size: 18),
      ),
    );
  }
}
