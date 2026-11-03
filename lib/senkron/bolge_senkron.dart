import '../api/api_istemci.dart';
import '../veri/bolge_deposu.dart';

/// Bölge bilgileri için senkron adımları (SenkronMotoru içinden çağrılır): önce yerel değişiklikleri GÖNDERİR, sonra sunucudakileri ÇEKER.
class BolgeSenkron {
  BolgeSenkron(this.api, this.depo);

  final ApiIstemci api;
  final BolgeDeposu depo;

  /// Sunucuda uçlar yoksa ya da kullanıcının Bölge yetkisi yoksa false olur; o turda atlanır.
  bool kullanilabilir = true;
  int indirilen = 0;

  Future<void> senkronla(bool Function() durdu) async {
    try {
      await _gonder(durdu);
      await _cek(durdu);
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

  /// İlk kurulumda (imleç yokken): en yeni 50 kayıt hemen indirilir; tam yükleme arkadan sürer.
  Future<void> hizliIlk() async {
    if (await depo.meta('bl_imlec') != null) return;
    try {
      final v = await api.get('bolgeler/degisenler?hizli=50');
      await depo.sunucudanYaz([
        for (final x in (v['degisen'] as List))
          Map<String, dynamic>.from(x as Map),
      ], const []);
      await _referansYenile();
    } on ApiHata catch (e) {
      if (e.durum == 403 || e.durum == 404) return;
      rethrow;
    }
  }

  Future<void> _gonder(bool Function() durdu) async {
    final sorunlu = (await depo.sorunlular()).keys.toSet();
    for (final op in await depo.kuyruk(durum: 'bekliyor')) {
      if (durdu()) return;
      if (sorunlu.contains(op.yerelId)) continue;
      try {
        if (op.tur == 'kaydet') {
          final v = await api.post(
            'bolgeler/kaydet',
            govde: {
              'istemci_id': op.istemciId,
              if (op.no != null) 'no': op.no,
              if (op.no != null && op.taban != null) 'taban': op.taban,
              'alanlar': op.govde,
            },
          );
          await depo.islemBasarili(
            op,
            sunucuBolge: Map<String, dynamic>.from(v['bolge'] as Map),
          );
        } else {
          try {
            await api.post(
              'bolgeler/sil',
              govde: {'istemci_id': op.istemciId, 'no': op.no},
            );
          } on ApiHata catch (e) {
            if (e.durum != 404) rethrow;
          }
          await depo.islemBasarili(op);
        }
      } on ApiHata catch (e) {
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

  Future<void> _cek(bool Function() durdu) async {
    var imlec = await depo.meta('bl_imlec');
    var tam = imlec == null;
    if (tam) indirilen = 0;

    while (!durdu()) {
      final q = <String, String>{'limit': '300', 'imlec': ?imlec};
      Map<String, dynamic> v;
      try {
        v = await api.get(
          'bolgeler/degisenler?${Uri(queryParameters: q).query}',
        );
      } on ApiHata catch (e) {
        if (e.durum == 410) {
          await depo.metaYaz('bl_imlec', null);
          imlec = null;
          tam = true;
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
      await depo.metaYaz('bl_imlec', imlec);
      indirilen += degisen.length;
      if (v['devam'] != true) break;
    }

    final son = int.tryParse(await depo.meta('bl_uzlastirma') ?? '') ?? 0;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    if (tam || simdi - son > const Duration(hours: 24).inMilliseconds) {
      final v = await api.get('bolgeler/idler');
      final idler = {for (final x in (v['idler'] as List)) (x as num).toInt()};
      await depo.uzlastir(idler);
      await depo.metaYaz('bl_uzlastirma', simdi.toString());
    }
  }

  Future<void> _referans() async {
    final son = int.tryParse(await depo.meta('bl_referans_zamani') ?? '') ?? 0;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    final bos = (await depo.referans()).isEmpty;
    if (!bos && simdi - son < const Duration(minutes: 30).inMilliseconds) {
      return;
    }
    await _referansYenile();
  }

  Future<void> _referansYenile() async {
    final v = await api.get('bolgeler/referans');
    await depo.referansYaz(v);
    await depo.metaYaz(
      'bl_referans_zamani',
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }
}
