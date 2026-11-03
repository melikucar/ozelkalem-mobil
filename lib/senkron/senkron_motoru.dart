import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'dart:io';

import '../api/api_istemci.dart';
import '../ayarlar.dart';
import '../veri/adres_servisi.dart';
import '../veri/program_deposu.dart';
import '../veri/talep_deposu.dart';
import 'program_senkron.dart';
import 'randevu_senkron.dart';
import 'faaliyet_senkron.dart';
import 'rehber_senkron.dart';
import 'yazisma_senkron.dart';
import 'tbmm_senkron.dart';
import 'bolge_senkron.dart';
import '../veri/rehber_deposu.dart';
import '../veri/faaliyet_deposu.dart';
import '../veri/randevu_deposu.dart';
import '../veri/yazisma_deposu.dart';
import '../veri/tbmm_deposu.dart';
import '../veri/bolge_deposu.dart';

/// Yerel veritabanı ile sunucu arasındaki senkron: önce yerel değişiklikleri GÖNDERİR, sonra sunucudaki değişiklikleri ÇEKER.
///
/// - Ekranlar yalnızca yerel veritabanını okur; ağ yoksa uygulama aynen çalışır, değişiklikler kuyrukta birikir.
/// - Gönderim sırayla yapılır; ağ/sunucu hatasında durur ve bir sonraki denemede kaldığı yerden sürer.
/// - Çakışma (409) ve doğrulama hataları kuyrukta "sorunlu" olarak işaretlenir, diğer kayıtların gönderimi engellenmez.
/// - Çekme imleç tabanlıdır; ilk yükleme sayfa sayfa yapılır, yarıda kesilirse kaldığı yerden sürer.
class SenkronMotoru extends ChangeNotifier {
  SenkronMotoru(
    this.api,
    this.depo, {
    this.programlar,
    this.randevular,
    this.faaliyetler,
    this.rehber,
    this.yazismalar,
    this.tbmm,
    this.bolgeler,
    DateTime Function()? simdi,
  }) : _simdi = simdi ?? DateTime.now {
    depo.yerelYazildi = _yakindaSenkronla;
    programlar?.yerelYazildi = _yakindaSenkronla;
    randevular?.yerelYazildi = _yakindaSenkronla;
    faaliyetler?.yerelYazildi = _yakindaSenkronla;
    rehber?.yerelYazildi = _yakindaSenkronla;
    yazismalar?.yerelYazildi = _yakindaSenkronla;
    tbmm?.yerelYazildi = _yakindaSenkronla;
    bolgeler?.yerelYazildi = _yakindaSenkronla;
    if (programlar != null) _program = ProgramSenkron(api, programlar!);
    if (randevular != null) _randevu = RandevuSenkron(api, randevular!);
    if (faaliyetler != null) _faaliyet = FaaliyetSenkron(api, faaliyetler!);
    if (rehber != null) _rehber = RehberSenkron(api, rehber!);
    if (yazismalar != null) _yazisma = YazismaSenkron(api, yazismalar!);
    if (tbmm != null) _tbmm = TbmmSenkron(api, tbmm!);
    if (bolgeler != null) _bolge = BolgeSenkron(api, bolgeler!);
  }

  final ApiIstemci api;
  final TalepDeposu depo;

  /// Programlar (ajanda takvimi) deposu; verilmezse yalnızca talepler senkronlanır.
  final ProgramDeposu? programlar;
  ProgramSenkron? _program;
  ProgramSenkron? get programSenkron => _program;

  /// Randevular deposu; verilmezse randevular senkronlanmaz.
  final RandevuDeposu? randevular;
  RandevuSenkron? _randevu;
  RandevuSenkron? get randevuSenkron => _randevu;

  /// Faaliyetler deposu; verilmezse faaliyetler senkronlanmaz.
  final FaaliyetDeposu? faaliyetler;
  FaaliyetSenkron? _faaliyet;
  FaaliyetSenkron? get faaliyetSenkron => _faaliyet;

  /// Rehber (kişiler + telefon görüşmeleri) deposu; verilmezse rehber senkronlanmaz.
  final RehberDeposu? rehber;
  RehberSenkron? _rehber;
  RehberSenkron? get rehberSenkron => _rehber;

  /// Yazışmalar deposu; verilmezse yazışmalar senkronlanmaz.
  final YazismaDeposu? yazismalar;
  YazismaSenkron? _yazisma;
  YazismaSenkron? get yazismaSenkron => _yazisma;

  /// TBMM (kanun teklifi / önergeler) deposu; verilmezse senkronlanmaz.
  final TbmmDeposu? tbmm;
  TbmmSenkron? _tbmm;
  TbmmSenkron? get tbmmSenkron => _tbmm;
  final BolgeDeposu? bolgeler;
  BolgeSenkron? _bolge;
  final DateTime Function() _simdi;

  /// 2: ilk yükleme tarih sınırsız ve en yeniden eskiye.
  static const _yuklemeSurumu = '2';

  bool calisiyor = false;

  /// Cihazdaki toplam kayıt sayısını verir ("eşitlendi" mesajında gösterilir); veri katmanı tarafından atanır.
  Future<int> Function()? kayitSayaci;

  /// Kullanıcı elle eşitleme istediğinde (aşağı çekme, düğme) hızlı biten turlar bile görünür kalsın diye gösterge en az bu kadar sürer.
  static const _enAzGosterge = Duration(milliseconds: 1000);
  DateTime? _gostergeBitis;
  Timer? _gostergeZamani;

  /// Başlıktaki "yükleniyor" simgesi: eşitleme sürerken ya da elle istenen eşitlemenin en az süresi dolmadan görünür.
  bool get gosterge =>
      calisiyor ||
      (_gostergeBitis != null && DateTime.now().isBefore(_gostergeBitis!));

  /// Elle (aşağı çekerek / düğmeyle) eşitleme: gösterge hemen başlar.
  Future<void> elleSenkronla() {
    _gostergeBitis = DateTime.now().add(_enAzGosterge);
    _gostergeZamani?.cancel();
    _gostergeZamani = Timer(
      _enAzGosterge + const Duration(milliseconds: 30),
      () {
        if (!_durdu) notifyListeners();
      },
    );
    notifyListeners();
    return senkronla();
  }

  bool ilkYukleme = false;
  int indirilen = 0;
  bool cevrimdisi = false;
  String? sonHata;
  DateTime? sonBasarili;
  int kuyrukSayisi = 0;

  Timer? _zamanlayici;
  Timer? _gecikme;
  StreamSubscription<List<ConnectivityResult>>? _baglanti;
  bool _durdu = false;

  /// Uygulama açıkken: açılışta, periyodik olarak ve bağlantı geri geldiğinde senkronlar.
  void baslat() {
    _zamanlayici = Timer.periodic(senkronAraligi, (_) => senkronla());
    _baglanti = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) senkronla();
    });
    senkronla();
  }

  void _yakindaSenkronla() {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(seconds: 1), senkronla);
    _kuyrukSayisiniYenile();
  }

  Future<void> _kuyrukSayisiniYenile() async {
    kuyrukSayisi = await _toplamKuyruk();
    notifyListeners();
  }

  Future<int> _toplamKuyruk() async =>
      await depo.kuyrukSayisi() +
      (await programlar?.kuyrukSayisi() ?? 0) +
      (await randevular?.kuyrukSayisi() ?? 0) +
      (await faaliyetler?.kuyrukSayisi() ?? 0) +
      (await rehber?.kuyrukSayisi() ?? 0) +
      (await yazismalar?.kuyrukSayisi() ?? 0) +
      (await tbmm?.kuyrukSayisi() ?? 0) +
      (await bolgeler?.kuyrukSayisi() ?? 0);

  @override
  void dispose() {
    _durdu = true;
    _zamanlayici?.cancel();
    _gecikme?.cancel();
    _gostergeZamani?.cancel();
    _baglanti?.cancel();
    depo.yerelYazildi = null;
    programlar?.yerelYazildi = null;
    randevular?.yerelYazildi = null;
    faaliyetler?.yerelYazildi = null;
    rehber?.yerelYazildi = null;
    yazismalar?.yerelYazildi = null;
    tbmm?.yerelYazildi = null;
    bolgeler?.yerelYazildi = null;
    super.dispose();
  }

  bool _onarildi = false;

  /// Cihazda hiç talep yokken sunucu özeti talep olduğunu söylüyorsa (eşitleme imleci eski/başka bir kayıttan kalmış ya da yerel veri
  /// silinmiş olabilir) imleç sıfırlanır; sonraki tur talepleri baştan indirir. Oturum başına bir kez denenir.
  Future<void> _bosListeyiOnar() async {
    if (_onarildi || ilkYukleme) return;
    if (await depo.sayi() > 0) return;
    final j = await depo.meta('ana_ozet');
    if (j == null) return;
    try {
      final top = ((jsonDecode(j) as Map)['rakamlar'] as Map?)?['toplam_talep'];
      if (top is num && top > 0) {
        _onarildi = true;
        await depo.imleciSifirla();
        _yakindaSenkronla();
      }
    } catch (_) {}
  }

  /// Tek bir senkron turu. Aynı anda ikinci tur başlamaz.
  Future<void> senkronla() async {
    if (calisiyor || _durdu) return;
    calisiyor = true;
    sonHata = null;
    notifyListeners();
    try {
      await _gonder();
      await _hizliIlk();
      await _cek();
      await _bosListeyiOnar();
      await _referans();
      await _program?.senkronla(() => _durdu);
      await _randevu?.senkronla(() => _durdu);
      await _faaliyet?.senkronla(() => _durdu);
      await _rehber?.senkronla(() => _durdu);
      await _yazisma?.senkronla(() => _durdu);
      await _tbmm?.senkronla(() => _durdu);
      await _bolge?.senkronla(() => _durdu);
      cevrimdisi = false;
      sonBasarili = _simdi();
    } on ApiHata catch (e) {
      cevrimdisi = e.agHatasi;
      sonHata = e.mesaj;
    } catch (e) {
      sonHata = e.toString();
    } finally {
      calisiyor = false;
      ilkYukleme = false;
      if (!_durdu) {
        kuyrukSayisi = await _toplamKuyruk();
        notifyListeners();
      }
    }
  }

  /// Son eşitlemeden gelen kullanıcıya gösterilecek mesaj (SMS sonucu, rehber işlemi). [mesajNo] her yeni mesajda artar.
  String? sonMesaj;
  int mesajNo = 0;

  void _sonucMesajlari(Map<String, dynamic> v) {
    final parcalar = <String>[];
    for (final x in (v['sms'] as List? ?? const [])) {
      final m = x as Map;
      parcalar.add(
        'SMS (${m['hedef']}): ${m['basarili'] == true ? 'gönderildi' : (m['mesaj'] ?? 'gönderilemedi')}',
      );
    }
    final r = v['rehber'];
    if (r is String && r.isNotEmpty) parcalar.add(r);
    if (parcalar.isEmpty) return;
    sonMesaj = parcalar.join('\n');
    mesajNo++;
  }

  /// Bir talebin tam ayrıntısını (adres adları, kaydeden, SMS'ler, dosyalar, geçmiş...) sunucudan alıp cihazda saklar.
  Future<Map<String, dynamic>> ayrintiGetir(int no) async {
    final v = await api.get('talepler/detay?no=$no');
    await depo.ekYaz(no, v);
    return v;
  }

  // ------------------------------------------------------------------ gönder

  Future<void> _gonder() async {
    final sorunlu = (await depo.sorunlular()).keys.toSet();
    for (final op in await depo.kuyruk(durum: 'bekliyor')) {
      if (_durdu) return;
      if (sorunlu.contains(op.yerelId)) {
        continue; // aynı kaydın çakışması çözülmeden sonraki işlemi gönderme
      }
      try {
        if (op.tur == 'kaydet') {
          final g = Map<String, dynamic>.from(op.govde);
          final ekstra = g.remove(
            '_ekstra',
          ); // SMS, rehbere kayıt, kara liste...
          final v = await api.post(
            'talepler/kaydet',
            govde: {
              'istemci_id': op.istemciId,
              if (op.no != null) 'no': op.no,
              if (op.no != null && op.taban != null) 'taban': op.taban,
              'alanlar': g,
              if (ekstra is Map && ekstra.isNotEmpty) 'ekstra': ekstra,
            },
          );
          await depo.islemBasarili(
            op,
            sunucuTalep: Map<String, dynamic>.from(v['talep'] as Map),
          );
          _sonucMesajlari(v);
        } else if (op.tur == 'dosya') {
          final g = op.govde;
          final no = op.no ?? await depo.noBul(op.yerelId);
          if (no == null) {
            continue; // talep henüz sunucuya gitmedi; sıradaki turda
          }
          final yol = g['yol'] as String;
          if (!File(yol).existsSync()) {
            await depo.islemSorunlu(op, 'hata', 'Dosya cihazda bulunamadı.');
            continue;
          }
          await api.yukle(
            'talepler/dosya-yukle',
            alanlar: {'istemci_id': op.istemciId, 'no': '$no'},
            dosyaAlani: 'dosya',
            dosyaYolu: yol,
            dosyaAdi: g['ad'] as String,
          );
          await depo.islemBasarili(op);
          try {
            await File(yol).delete();
          } catch (_) {}
          try {
            await ayrintiGetir(no);
          } catch (_) {}
        } else if (op.tur == 'dosya_sil') {
          final no = op.no ?? await depo.noBul(op.yerelId);
          if (no == null) continue;
          try {
            await api.post(
              'talepler/dosya-sil',
              govde: {
                'istemci_id': op.istemciId,
                'no': no,
                'ad': op.govde['ad'],
              },
            );
          } on ApiHata catch (e) {
            if (e.durum != 404) rethrow; // dosya sunucuda zaten yok
          }
          await depo.islemBasarili(op);
          try {
            await ayrintiGetir(no);
          } catch (_) {}
        } else {
          try {
            await api.post(
              'talepler/sil',
              govde: {'istemci_id': op.istemciId, 'no': op.no},
            );
          } on ApiHata catch (e) {
            if (e.durum != 404) rethrow; // sunucuda zaten yok: silinmiş say
          }
          await depo.islemBasarili(op);
        }
      } on ApiHata catch (e) {
        // Ağ/sunucu/oturum sorunları tüm turu durdurur; işlem kuyrukta kalır
        if (e.agHatasi || e.durum >= 500 || e.durum == 429 || e.durum == 401) {
          rethrow;
        }
        if (e.kod == 'cakisma') {
          final s = e.ek['sunucu'];
          await depo.islemSorunlu(
            op,
            'cakisma',
            e.mesaj,
            sunucu: s is Map ? Map<String, dynamic>.from(s) : null,
          );
        } else {
          await depo.islemSorunlu(op, 'hata', e.mesaj);
        }
      }
    }
  }

  // ------------------------------------------------------------------ hızlı ilk görünüm

  /// İlk kurulumda her modülün tarihe göre en yeni 50 kaydı hemen indirilir; ekranlar anında dolar, tam yükleme sonra sürer.
  Future<void> _hizliIlk() async {
    Future<void> talepler() async {
      if (await depo.meta('imlec') != null) return;
      final v = await api.get('talepler/degisenler?hizli=50');
      await depo.sunucudanYaz([
        for (final x in (v['degisen'] as List))
          Map<String, dynamic>.from(x as Map),
      ], const []);
      await _referans();
    }

    // Modüllerin hızlı görünümleri aynı anda istenir: biri yavaş kalsa da diğerleri hemen dolar.
    await Future.wait([
      talepler(),
      if (_program != null) _program!.hizliIlk(),
      if (_randevu != null) _randevu!.hizliIlk(),
      if (_faaliyet != null) _faaliyet!.hizliIlk(),
      if (_rehber != null) _rehber!.hizliIlk(),
      if (_yazisma != null) _yazisma!.hizliIlk(),
      if (_tbmm != null) _tbmm!.hizliIlk(),
      if (_bolge != null) _bolge!.hizliIlk(),
    ]);
  }

  // ------------------------------------------------------------------ çek

  Future<void> _cek() async {
    // İlk yükleme kuralları değiştiğinde (ör. tarih sınırının kalkması) kayıtlı imleç atılır, baştan yüklenir.
    // İşaret hiç yoksa (yarım kalmış yükleme) mevcut kurallarla başlatılmıştır: imleçten sürer, baştan başlamaz.
    final kayitliSurum = await depo.meta('yukleme_surumu');
    if (kayitliSurum != null && kayitliSurum != _yuklemeSurumu) {
      await depo.imleciSifirla();
    }
    var imlec = await depo.meta('imlec');
    var tam = imlec == null;
    if (tam) {
      ilkYukleme = true;
      indirilen = 0;
      notifyListeners();
    }
    // Sürüm işareti yükleme BAŞLARKEN yazılır: yükleme (ağ hatası, uygulamanın kapanması...) yarıda kesilse bile
    // sonraki tur kaldığı yerden devam eder; 27 bin kaydın baştan indirilmesi gerekmez.
    if (kayitliSurum != _yuklemeSurumu) {
      await depo.metaYaz('yukleme_surumu', _yuklemeSurumu);
    }

    while (!_durdu) {
      final q = <String, String>{
        'limit': '300',
        'imlec': ?imlec,
        if (imlec == null && ilkYuklemeAy > 0)
          'tarih_baslangic': _tarihBaslangic(),
      };
      Map<String, dynamic> v;
      try {
        v = await api.get(
          'talepler/degisenler?${Uri(queryParameters: q).query}',
        );
      } on ApiHata catch (e) {
        if (e.durum == 410) {
          // Sunucu günlüğü temizlenmiş: baştan yükle
          await depo.imleciSifirla();
          imlec = null;
          tam = true;
          ilkYukleme = true;
          continue;
        }
        rethrow;
      }
      final degisen = [
        for (final x in (v['degisen'] as List))
          Map<String, dynamic>.from(x as Map),
      ];
      final silinen = [
        for (final x in (v['silinen'] as List)) (x as num).toInt(),
      ];
      await depo.sunucudanYaz(degisen, silinen);
      imlec = v['imlec'] as String;
      await depo.metaYaz('imlec', imlec);
      indirilen += degisen.length;
      notifyListeners();
      if (v['devam'] != true) break;
    }

    await depo.metaYaz('yukleme_surumu', _yuklemeSurumu);

    // Tam yüklemeden sonra ve günde bir: sunucuda artık görünmeyen yerel kayıtları temizle
    final son = int.tryParse(await depo.meta('uzlastirma') ?? '') ?? 0;
    if (tam ||
        _simdi().millisecondsSinceEpoch - son >
            const Duration(hours: 24).inMilliseconds) {
      await _uzlastir();
    }
  }

  Future<void> _uzlastir() async {
    final v = await api.get('talepler/idler');
    final idler = {for (final x in (v['idler'] as List)) (x as num).toInt()};
    await depo.uzlastir(idler);
    await depo.metaYaz(
      'uzlastirma',
      _simdi().millisecondsSinceEpoch.toString(),
    );
  }

  String _tarihBaslangic() {
    final n = _simdi();
    final d = DateTime(n.year, n.month - ilkYuklemeAy, n.day);
    String iki(int x) => x.toString().padLeft(2, '0');
    return '${d.year}-${iki(d.month)}-${iki(d.day)}';
  }

  // ------------------------------------------------------------------ referans

  Future<void> _referans() async {
    final son = int.tryParse(await depo.meta('referans_zamani') ?? '') ?? 0;
    final bos =
        (await depo.durumlar()).isEmpty ||
        !(await depo.referansEk()).containsKey('kaydedenler');
    if (!bos &&
        _simdi().millisecondsSinceEpoch - son <
            const Duration(minutes: 10).inMilliseconds) {
      return;
    }
    final v = await api.get('talepler/referans');
    await depo.referansYaz(
      durumlar: [
        for (final x in (v['durumlar'] as List))
          Map<String, dynamic>.from(x as Map),
      ],
      kategoriler: [
        for (final x in (v['kategoriler'] as List))
          Map<String, dynamic>.from(x as Map),
      ],
      ek: {
        'rehber_kategorileri': v['rehber_kategorileri'] ?? [],
        'kaydedenler': v['kaydedenler'] ?? [],
        'varsayilan_il': v['varsayilan_il'] ?? 0,
        'sms_hazir': v['sms_hazir'] ?? false,
      },
    );
    // Form çevrimdışı da açılsın: il listesi ve makamın ilinin ilçeleri önceden indirilir
    try {
      final adres = AdresServisi(api, depo);
      await adres.iller();
      final il = (v['varsayilan_il'] as num?)?.toInt() ?? 0;
      if (il > 0) await adres.ilceler(il);
    } on ApiHata {
      // ağ yoksa sonraki turda
    }
    await depo.metaYaz(
      'referans_zamani',
      _simdi().millisecondsSinceEpoch.toString(),
    );
  }
}
