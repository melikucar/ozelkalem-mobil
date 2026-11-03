import '../api/api_istemci.dart';
import '../veri/randevu_deposu.dart';

/// Randevular için senkron adımları (SenkronMotoru içinden çağrılır): önce yerel değişiklikleri GÖNDERİR, sonra sunucudakileri ÇEKER.
class RandevuSenkron {
  RandevuSenkron(this.api, this.depo);

  final ApiIstemci api;
  final RandevuDeposu depo;

  /// Sunucuda uçlar yoksa ya da kullanıcının Ajanda yetkisi yoksa false olur; o turda randevular atlanır.
  bool kullanilabilir = true;

  /// Son gönderimde sunucudan gelen uyarılar (SMS sonucu, takvim çakışması …) — ekran bir kez okuyup temizler.
  final List<String> bildirimler = [];

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

  /// İlk kurulumda (imleç yokken): tarihe göre en yeni 50 kayıt hemen indirilir; modüller anında dolar, tam yükleme arkadan sürer.
  Future<void> hizliIlk() async {
    if (await depo.meta('r_imlec') != null) return;
    try {
      final v = await api.get('randevular/degisenler?hizli=50');
      await depo.sunucudanYaz([
        for (final x in (v['degisen'] as List))
          Map<String, dynamic>.from(x as Map),
      ], const []);
      await _referans(); // kategori / durum adları ekranlarda hemen görünsün
    } on ApiHata catch (e) {
      if (e.durum == 403 || e.durum == 404) return;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> ayrintiGetir(int no) async {
    final v = await api.get('randevular/detay?no=$no');
    await depo.ekYaz(no, v);
    return v;
  }

  Future<List<Map<String, dynamic>>> musaitlik(
    String tarih,
    int sureDk,
    int? no,
  ) async {
    final q = Uri(
      queryParameters: {
        'tarih': tarih,
        'sure_dk': '$sureDk',
        if (no != null) 'no': '$no',
      },
    ).query;
    final v = await api.get('randevular/musaitlik?$q');
    return [
      for (final x in (v['cakisma'] as List? ?? const []))
        Map<String, dynamic>.from(x as Map),
    ];
  }

  Future<void> _gonder(bool Function() durdu) async {
    final sorunlu = (await depo.sorunlular()).keys.toSet();
    for (final op in await depo.kuyruk(durum: 'bekliyor')) {
      if (durdu()) return;
      if (sorunlu.contains(op.yerelId)) continue;
      try {
        if (op.tur == 'kaydet') {
          final g = Map<String, dynamic>.from(op.govde);
          final hat = g.remove('_hat');
          final ek = g.remove('_ek');
          final v = await api.post(
            'randevular/kaydet',
            govde: {
              'istemci_id': op.istemciId,
              if (op.no != null) 'no': op.no,
              if (op.no != null && op.taban != null) 'taban': op.taban,
              'alanlar': g,
              'hatirlatici': ?hat,
              'ekstra': ?ek,
            },
          );
          for (final s in (v['sms'] as List? ?? const [])) {
            final m = s as Map;
            bildirimler.add(
              '${m['basarili'] == true ? 'SMS gitti' : 'SMS gitmedi'}: ${m['mesaj'] ?? ''}',
            );
          }
          await depo.islemBasarili(
            op,
            sunucuRandevu: Map<String, dynamic>.from(v['randevu'] as Map),
          );
        } else {
          try {
            await api.post(
              'randevular/sil',
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
    var imlec = await depo.meta('r_imlec');
    var tam = imlec == null;

    while (!durdu()) {
      final q = <String, String>{'limit': '300', 'imlec': ?imlec};
      Map<String, dynamic> v;
      try {
        v = await api.get(
          'randevular/degisenler?${Uri(queryParameters: q).query}',
        );
      } on ApiHata catch (e) {
        if (e.durum == 410) {
          await depo.metaYaz('r_imlec', null);
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
      await depo.metaYaz('r_imlec', imlec);
      if (v['devam'] != true) break;
    }

    final son = int.tryParse(await depo.meta('r_uzlastirma') ?? '') ?? 0;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    if (tam || simdi - son > const Duration(hours: 24).inMilliseconds) {
      final v = await api.get('randevular/idler');
      final idler = {for (final x in (v['idler'] as List)) (x as num).toInt()};
      await depo.uzlastir(idler);
      await depo.metaYaz('r_uzlastirma', simdi.toString());
    }
  }

  Future<void> _referans() async {
    final son = int.tryParse(await depo.meta('r_referans_zamani') ?? '') ?? 0;
    final simdi = DateTime.now().millisecondsSinceEpoch;
    final bos = (await depo.referans()).isEmpty;
    if (!bos && simdi - son < const Duration(minutes: 30).inMilliseconds) {
      return;
    }
    final v = await api.get('randevular/referans');
    await depo.referansYaz(v);
    await depo.metaYaz('r_referans_zamani', simdi.toString());
  }
}
