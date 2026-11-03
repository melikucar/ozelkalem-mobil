import '../api/api_istemci.dart';
import '../veri/rehber_deposu.dart';

/// Rehber (kişiler + telefon görüşmeleri) için senkron adımları (SenkronMotoru içinden çağrılır):
/// önce yerel değişiklikleri GÖNDERİR, sonra sunucudakileri ÇEKER.
class RehberSenkron {
  RehberSenkron(this.api, this.depo);

  final ApiIstemci api;
  final RehberDeposu depo;

  /// Sunucuda uçlar yoksa ya da kullanıcının Telefonlar yetkisi yoksa false olur; o turda rehber atlanır.
  bool kullanilabilir = true;

  static const _yol = {
    RehberVarlik.kisi: 'rehber',
    RehberVarlik.gorusme: 'gorusme',
  };
  static const _on = {RehberVarlik.kisi: 'rk_', RehberVarlik.gorusme: 'rg_'};

  /// Kaydın sunucu yanıtındaki anahtarı.
  static const _sonucAnahtari = {
    RehberVarlik.kisi: 'kisi',
    RehberVarlik.gorusme: 'gorusme',
  };

  Future<void> senkronla(bool Function() durdu) async {
    try {
      for (final v in RehberVarlik.values) {
        await _gonder(v, durdu);
      }
      for (final v in RehberVarlik.values) {
        await _cek(v, durdu);
      }
      await _referans();
      kullanilabilir = true;
    } on ApiHata catch (e) {
      if (e.durum == 403 || e.durum == 404) {
        kullanilabilir = false;
        return;
      }
      rethrow;
    }
  }

  /// İlk kurulumda (imleç yokken): tarihe göre en yeni 50 kayıt hemen indirilir; ekranlar anında dolar, tam yükleme arkadan sürer.
  Future<void> hizliIlk() async {
    try {
      for (final v in RehberVarlik.values) {
        if (await depo.meta('${_on[v]}imlec') != null) continue;
        final r = await api.get('${_yol[v]}/degisenler?hizli=50');
        await depo.sunucudanYaz(v, [
          for (final x in (r['degisen'] as List))
            Map<String, dynamic>.from(x as Map),
        ], const []);
      }
      await _referans();
    } on ApiHata catch (e) {
      if (e.durum == 403 || e.durum == 404) return;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> kisiAyrintisi(int no) async {
    final v = await api.get('rehber/detay?no=$no');
    await depo.ekYaz('kisi$no', v);
    return v;
  }

  Future<Map<String, dynamic>> gorusmeAyrintisi(int no) async {
    final v = await api.get('gorusme/detay?no=$no');
    await depo.ekYaz('gorusme$no', v);
    return v;
  }

  /// Kategori ayarları çevrimiçi çalışır; ardından referans hemen tazelenir.
  Future<void> kategoriKaydet(String adi, {int? no}) async {
    await api.post('rehber/kategori-kaydet', govde: {'adi': adi, 'no': ?no});
    await _referansYenile();
  }

  Future<void> kategoriSil(int no) async {
    await api.post('rehber/kategori-sil', govde: {'no': no});
    await _referansYenile();
  }

  Future<void> _gonder(RehberVarlik v, bool Function() durdu) async {
    final yol = _yol[v]!;
    final sorunlu = (await depo.sorunlular(v)).keys.toSet();
    for (final op in await depo.kuyruk(v, durum: 'bekliyor')) {
      if (durdu()) return;
      if (sorunlu.contains(op.yerelId)) continue;
      try {
        if (op.tur == 'kaydet') {
          final g = Map<String, dynamic>.from(op.govde);
          final ek = g.remove('_ek');
          final r = await api.post(
            '$yol/kaydet',
            govde: {
              'istemci_id': op.istemciId,
              if (op.no != null) 'no': op.no,
              if (op.no != null && op.taban != null) 'taban': op.taban,
              'alanlar': g,
              'ekstra': ?ek,
            },
          );
          await depo.islemBasarili(
            v,
            op,
            sunucu: Map<String, dynamic>.from(r[_sonucAnahtari[v]!] as Map),
          );
        } else {
          try {
            await api.post(
              '$yol/sil',
              govde: {'istemci_id': op.istemciId, 'no': op.no},
            );
          } on ApiHata catch (e) {
            if (e.durum != 404) rethrow;
          }
          await depo.islemBasarili(v, op);
        }
      } on ApiHata catch (e) {
        if (e.agHatasi || e.durum >= 500 || e.durum == 429 || e.durum == 401) {
          rethrow;
        }
        if (e.kod == 'cakisma') {
          final s = e.ek['sunucu'];
          await depo.islemSorunlu(
            v,
            op,
            'cakisma',
            e.mesaj,
            sunucu: s is Map ? Map<String, dynamic>.from(s) : null,
          );
        } else {
          await depo.islemSorunlu(v, op, 'hata', e.mesaj);
        }
      }
    }
  }

  Future<void> _cek(RehberVarlik v, bool Function() durdu) async {
    final yol = _yol[v]!;
    final on = _on[v]!;
    var imlec = await depo.meta('${on}imlec');
    var tam = imlec == null;

    while (!durdu()) {
      final q = <String, String>{'limit': '500', 'imlec': ?imlec};
      Map<String, dynamic> r;
      try {
        r = await api.get('$yol/degisenler?${Uri(queryParameters: q).query}');
      } on ApiHata catch (e) {
        if (e.durum == 410) {
          await depo.metaYaz('${on}imlec', null);
          imlec = null;
          tam = true;
          continue;
        }
        rethrow;
      }
      final degisen = [
        for (final x in (r['degisen'] as List))
          Map<String, dynamic>.from(x as Map),
      ];
      final silinen = [
        for (final x in (r['silinen'] as List)) (x as num).toInt(),
      ];
      await depo.sunucudanYaz(v, degisen, silinen);
      imlec = r['imlec'] as String;
      await depo.metaYaz('${on}imlec', imlec);
      if (r['devam'] != true) break;
    }

    final son = int.tryParse(await depo.meta('${on}uzlastirma') ?? '') ?? 0;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    if (tam || simdi - son > const Duration(hours: 24).inMilliseconds) {
      final r = await api.get('$yol/idler');
      final idler = {for (final x in (r['idler'] as List)) (x as num).toInt()};
      await depo.uzlastir(v, idler);
      await depo.metaYaz('${on}uzlastirma', simdi.toString());
    }
  }

  Future<void> _referans() async {
    final son = int.tryParse(await depo.meta('h_referans_zamani') ?? '') ?? 0;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    final bos = (await depo.referans()).isEmpty;
    if (!bos && simdi - son < const Duration(minutes: 30).inMilliseconds) {
      return;
    }
    await _referansYenile();
  }

  Future<void> _referansYenile() async {
    final v = await api.get('rehber/referans');
    await depo.referansYaz(v);
    await depo.metaYaz(
      'h_referans_zamani',
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }
}
