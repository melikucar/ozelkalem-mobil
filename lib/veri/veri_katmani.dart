import '../api/oturum.dart';
import '../ayarlar.dart';
import '../senkron/senkron_motoru.dart';
import 'adres_servisi.dart';
import 'program_deposu.dart';
import 'randevu_deposu.dart';
import 'faaliyet_deposu.dart';
import 'rehber_deposu.dart';
import 'talep_deposu.dart';
import 'yazisma_deposu.dart';
import 'tbmm_deposu.dart';
import 'bolge_deposu.dart';
import 'yerel_db.dart';

/// Oturum açık kullanıcının yerel veritabanı + depo + senkron motoru. Giriş yapılınca açılır, oturum kapanınca kapanır.
class VeriKatmani {
  VeriKatmani._(
    this.yerel,
    this.dosya,
    this.talepler,
    this.programlar,
    this.randevular,
    this.faaliyetler,
    this.rehber,
    this.yazismalar,
    this.tbmm,
    this.bolgeler,
    this.motor,
    this.adres,
  );

  final YerelDb yerel;
  final String dosya;
  final TalepDeposu talepler;
  final ProgramDeposu programlar;
  final RandevuDeposu randevular;
  final FaaliyetDeposu faaliyetler;
  final RehberDeposu rehber;
  final YazismaDeposu yazismalar;
  final TbmmDeposu tbmm;
  final BolgeDeposu bolgeler;
  final SenkronMotoru motor;
  final AdresServisi adres;

  static Future<VeriKatmani> ac(Oturum oturum) async {
    final no = (oturum.ben?['yonetici'] as Map?)?['no'] ?? 0;
    // Canlı dışı bir sunucuya (yerel test) bağlı derlemeler ayrı veritabanı dosyası kullanır: iki sunucunun verisi/eşitleme imleci
    // asla karışmasın (canlı kullanıcıların dosya adı değişmez)
    final canli = apiTaban.startsWith('https://v7.ozelkalemotomasyonu.com');
    final dosya = canli ? 'ozelkalem_$no.db' : 'ozelkalem_test_$no.db';
    final yerel = await YerelDb.ac(dosya);
    final depo = TalepDeposu(yerel);
    final programlar = ProgramDeposu(yerel);
    final randevular = RandevuDeposu(yerel);
    final faaliyetler = FaaliyetDeposu(yerel);
    final rehber = RehberDeposu(yerel);
    final yazismalar = YazismaDeposu(yerel);
    final tbmm = TbmmDeposu(yerel);
    final bolgeler = BolgeDeposu(yerel);
    final motor = SenkronMotoru(
      oturum.api,
      depo,
      programlar: programlar,
      randevular: randevular,
      faaliyetler: faaliyetler,
      rehber: rehber,
      yazismalar: yazismalar,
      tbmm: tbmm,
      bolgeler: bolgeler,
    )..baslat();
    motor.kayitSayaci = () async =>
        await depo.sayi() +
        await programlar.sayi() +
        await randevular.sayi() +
        await faaliyetler.sayi() +
        await rehber.kisiSayisi() +
        await yazismalar.sayi() +
        await tbmm.sayi() +
        await bolgeler.sayi();
    return VeriKatmani._(
      yerel,
      dosya,
      depo,
      programlar,
      randevular,
      faaliyetler,
      rehber,
      yazismalar,
      tbmm,
      bolgeler,
      motor,
      AdresServisi(oturum.api, depo),
    );
  }

  /// [sil]: yerel veritabanı dosyası da silinir (çıkışta; gönderilmemiş değişiklikler kaybolur).
  Future<void> kapat({bool sil = false}) {
    // Birden çok yerden (çıkış ve ekranın kapanışı) çağrılabilir; gerçek kapatma bir kez, silme isteği hatırlanarak yapılır
    if (sil) silinecek = true;
    return _kapanis ??= _kapatGercek();
  }

  /// Çıkış yapılırken true: ekran kapanıp veri katmanı kapatılırken yerel veritabanı dosyası da silinir.
  bool silinecek = false;
  Future<void>? _kapanis;

  Future<void> _kapatGercek() async {
    motor.dispose();
    await yerel.kapat();
    if (silinecek) await YerelDb.sil(dosya);
  }
}
