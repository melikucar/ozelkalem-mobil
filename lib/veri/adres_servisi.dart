import '../api/api_istemci.dart';
import 'talep_deposu.dart';

/// İl > ilçe > semt > mahalle listeleri. Listeler sunucudan bir kez indirilip cihazda saklanır; ağ yoksa saklı olanlar kullanılır.
class AdresServisi {
  AdresServisi(this._api, this._depo);

  final ApiIstemci _api;
  final TalepDeposu _depo;

  Future<List<AdresOgesi>> _getir(String anahtar, String yol) async {
    final saklanan = await _depo.adresOku(anahtar);
    if (saklanan != null) return _coz(saklanan);
    final v = await _api.get(yol);
    final liste = (v['liste'] as List?) ?? const [];
    await _depo.adresYaz(anahtar, liste);
    return _coz(liste);
  }

  List<AdresOgesi> _coz(List<dynamic> l) => [
    for (final x in l) AdresOgesi((x as Map)['id'] as int, x['ad'] as String),
  ];

  Future<List<AdresOgesi>> iller() => _getir('il', 'adres/iller');
  Future<List<AdresOgesi>> ilceler(int il) =>
      _getir('ilce:$il', 'adres/ilceler?il=$il');
  Future<List<AdresOgesi>> semtler(int ilce) =>
      _getir('semt:$ilce', 'adres/semtler?ilce=$ilce');
  Future<List<AdresOgesi>> mahalleler(int semt) =>
      _getir('mahalle:$semt', 'adres/mahalleler?semt=$semt');
}

class AdresOgesi {
  const AdresOgesi(this.id, this.ad);

  final int id;
  final String ad;
}
