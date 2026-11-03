import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../tema/tema.dart';

import '../ayarlar.dart';
import 'api_istemci.dart';
import 'token_deposu.dart';

enum OturumDurumu {
  basliyor,
  girisGerekli,
  acik,
  baglantiYok,
  guncellemeZorunlu,
}

/// Uygulamanın oturum durumu. Ekranlar bunu dinleyerek giriş / ana ekran / güncelleme ekranı arasında geçer.
class Oturum extends ChangeNotifier {
  Oturum(this.depo) : api = ApiIstemci(depo) {
    api.oturumKapandi = () {
      ben = null;
      _durum = OturumDurumu.girisGerekli;
      mesaj = 'Oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın.';
      notifyListeners();
    };
  }

  final TokenDeposu depo;
  final ApiIstemci api;

  OturumDurumu _durum = OturumDurumu.basliyor;
  OturumDurumu get durum => _durum;

  /// GET /ben yanıtı: yonetici, makam, moduller, kisitlar
  Map<String, dynamic>? ben;

  /// Veriler sunucudan değil, önbellekten gösteriliyor.
  bool cevrimdisi = false;

  /// Ekranda gösterilecek son bilgi / hata mesajı.
  String? mesaj;

  String surum = yedekSurum;
  String? guncellemeAdresi;

  String get platform => Platform.isIOS ? 'ios' : 'android';

  List<String> get moduller => ((ben?['moduller'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();

  bool modulVar(String m) => moduller.contains(m);

  /// Kullanıcının kendi tema tercihi (web panelindeki ile aynı kayıt).
  TemaTercihi get tema => TemaTercihi.benden(ben?['yonetici'] as Map?);

  /// Makamın görseli (ayarlar.logo; cihazda saklanır); yoksa null → baş harfler gösterilir.
  Uint8List? makamResmi;

  /// Makamın imza görseli (imzalar/imza.png; cihazda saklanır).
  Uint8List? makamImza;

  /// Temayı hemen uygular ve sunucuya yazar. Sunucuya ulaşılamazsa tema bu cihazda kalır; sonraki girişte web'deki kayıt geçerli olur.
  Future<bool> temaKaydet(TemaTercihi t) async {
    final y = Map<String, dynamic>.from((ben?['yonetici'] as Map?) ?? {});
    y['tema_mode'] = t.mod;
    y['tema_stil'] = t.stil;
    y['tema_renk'] = t.renk;
    ben = {...?ben, 'yonetici': y};
    notifyListeners();
    await depo.benYaz(ben!);
    try {
      await api.post(
        'tema',
        govde: {'mod': t.mod, 'stil': t.stil, 'renk': t.renk},
      );
      return true;
    } on ApiHata {
      return false;
    }
  }

  /// Kullanıcının profil fotoğrafı (yoneticiler.fotograf); yoksa null → hesap simgesi gösterilir.
  Uint8List? profilFoto;

  /// Makam görseli ve profil fotoğrafını gerekirse indirir (sunucudaki özet değiştiyse); çevrimdışıysa saklı olanı kullanır.
  Future<void> resimYukle() async {
    makamResmi = await _gorsel(
      'makam',
      ((ben?['makam'] as Map?)?['resim_ozeti'])?.toString(),
      'makam/resim',
    );
    profilFoto = await _gorsel(
      'profil',
      ((ben?['yonetici'] as Map?)?['foto_ozeti'])?.toString(),
      'profil/foto',
    );
    makamImza = await _gorsel('imza', 'imza', 'makam/imza');
  }

  Future<Uint8List?> _gorsel(String ad, String? ozet, String yol) async {
    try {
      final saklanan = await depo.gorselOku(ad);
      if (ozet == null && ad != 'imza') {
        if (saklanan != null && !cevrimdisi) {
          await depo.gorselSil(ad); // sunucuda artık yok
        }
        return cevrimdisi ? saklanan?.bayt : null;
      }
      if (saklanan != null) {
        // saklı olanı hemen göster, güncel değilse arkadan yenile
        if (saklanan.ozet == ozet || cevrimdisi) return saklanan.bayt;
        makamVeyaFoto(ad, saklanan.bayt);
      } else if (cevrimdisi) {
        return null;
      }
      final bayt = await api.indir(yol);
      await depo.gorselYaz(ad, ozet ?? 'varsayilan', bayt);
      return bayt;
    } catch (_) {
      return (await depo.gorselOku(ad))
          ?.bayt; // görsel ikincil: indirilemezse eldeki / yer tutucu
    } finally {
      notifyListeners();
    }
  }

  void makamVeyaFoto(String ad, Uint8List bayt) {
    if (ad == 'makam') makamResmi = bayt;
    if (ad == 'profil') profilFoto = bayt;
    if (ad == 'imza') makamImza = bayt;
    notifyListeners();
  }

  /// Uygulama açılışı: sürüm denetimi → kayıtlı oturum var mı → /ben.
  Future<void> baslat() async {
    _durum = OturumDurumu.basliyor;
    mesaj = null;
    notifyListeners();

    try {
      surum = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    try {
      final s = await api.get(
        'surum?platform=$platform&surum=$surum',
        kimlik: false,
      );
      if (s['zorunlu'] == true) {
        guncellemeAdresi = s['indirme_adresi'] as String?;
        _durum = OturumDurumu.guncellemeZorunlu;
        notifyListeners();
        return;
      }
    } on ApiHata {
      // sürüm kontrolü yapılamadıysa (çevrimdışı) açılışı engelleme
    }

    if (!await depo.oturumVar) {
      _durum = OturumDurumu.girisGerekli;
      notifyListeners();
      return;
    }
    await benYukle();
  }

  /// Kullanıcı/makam/yetkileri tazeler. Ağ yoksa önbellekten açar.
  Future<void> benYukle() async {
    try {
      ben = await api.get('ben');
      await depo.benYaz(ben!);
      cevrimdisi = false;
      _durum = OturumDurumu.acik;
    } on ApiHata catch (e) {
      if (e.oturumGecersiz) return; // oturumKapandi zaten durumu ayarladı
      if (e.agHatasi || e.durum >= 500) {
        final onbellek = await depo.benOku();
        if (onbellek != null) {
          ben = onbellek;
          cevrimdisi = true;
          _durum = OturumDurumu.acik;
        } else {
          mesaj = e.mesaj;
          _durum = OturumDurumu.baglantiYok;
        }
      } else {
        // makam askıda, mobil kapalı vb.: yeniden giriş ekranı, mesajla
        await depo.oturumuTemizle();
        ben = null;
        mesaj = e.mesaj;
        _durum = OturumDurumu.girisGerekli;
      }
    }
    notifyListeners();
    if (_durum == OturumDurumu.acik) resimYukle();
  }

  /// Hata olursa [ApiHata] fırlatır (ekran mesajı gösterir).
  Future<void> giris(String tckn, String sifre) async {
    final v = await api.post(
      'auth/giris',
      kimlik: false,
      govde: {
        'tckn': tckn,
        'sifre': sifre,
        'cihaz': {
          'kimlik': await depo.cihazKimligi(),
          'ad': await _cihazAdi(),
          'platform': platform,
          'surum': surum,
        },
      },
    );
    await depo.belirtecYaz(
      v['access_token'] as String,
      v['refresh_token'] as String,
    );
    mesaj = null;
    await benYukle();
    if (_durum != OturumDurumu.acik) {
      throw ApiHata(0, 'giris_tamamlanamadi', mesaj ?? 'Giriş tamamlanamadı.');
    }
  }

  Future<void> cikis() async {
    try {
      await api.post('auth/cikis');
    } on ApiHata {
      // çevrimdışıysa yalnızca bu cihazdan çıkılır; sunucudaki oturum süresi dolunca kapanır
    }
    await depo.oturumuTemizle();
    ben = null;
    makamResmi = null;
    profilFoto = null;
    cevrimdisi = false;
    mesaj = null;
    _durum = OturumDurumu.girisGerekli;
    notifyListeners();
  }

  Future<String> _cihazAdi() async {
    try {
      final d = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await d.androidInfo;
        return '${a.manufacturer} ${a.model}';
      }
      if (Platform.isIOS) return (await d.iosInfo).name;
    } catch (_) {}
    return '';
  }
}
