import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../ayarlar.dart';
import 'token_deposu.dart';

/// Sunucunun {ok:false,hata:{kod,mesaj}} yanıtı ya da ağ hatası. [durum] 0 ise sunucuya hiç ulaşılamamıştır.
class ApiHata implements Exception {
  ApiHata(this.durum, this.kod, this.mesaj, [this.ek = const {}]);

  final int durum;
  final String kod;
  final String mesaj;

  /// Hata nesnesindeki ek alanlar (ör. 409'da `sunucu`: güncel kayıt).
  final Map<String, dynamic> ek;

  bool get agHatasi => durum == 0;

  /// Oturum sunucuda geçersiz: yeniden giriş gerekir.
  bool get oturumGecersiz =>
      durum == 401 &&
      const {
        'oturum_gecersiz',
        'oturum_gerekli',
        'makam_gecersiz',
      }.contains(kod);

  @override
  String toString() => 'ApiHata($durum, $kod, $mesaj)';
}

/// API istemcisi: Bearer belirteci ekler, süresi dolan access belirtecini tek seferde (aynı anda gelen
/// isteklerde bir kez) yeniler ve isteği tekrarlar. Oturum sunucuda kapanmışsa [oturumKapandi] çağrılır.
class ApiIstemci {
  ApiIstemci(this.depo, {http.Client? istemci})
    : _http = istemci ?? http.Client();

  final TokenDeposu depo;
  final http.Client _http;

  /// Oturum sunucu tarafında geçersiz olduğunda çağrılır (belirteçler zaten silinmiştir).
  void Function()? oturumKapandi;

  Future<void>? _yenileniyor;

  Future<Map<String, dynamic>> get(String yol, {bool kimlik = true}) =>
      _gonder('GET', yol, null, kimlik);

  Future<Map<String, dynamic>> post(
    String yol, {
    Map<String, dynamic>? govde,
    bool kimlik = true,
  }) => _gonder('POST', yol, govde ?? {}, kimlik);

  Future<Map<String, dynamic>> _gonder(
    String yontem,
    String yol,
    Map<String, dynamic>? govde,
    bool kimlik, {
    bool tekrar = false,
  }) async {
    final basliklar = <String, String>{
      'Accept': 'application/json',
      if (govde != null) 'Content-Type': 'application/json',
    };
    if (kimlik) {
      final a = await depo.access;
      if (a == null) throw ApiHata(401, 'oturum_gerekli', 'Oturum gerekli.');
      basliklar['Authorization'] = 'Bearer $a';
    }

    try {
      return await _tekIstek(yontem, yol, basliklar, govde);
    } on ApiHata catch (e) {
      if (kimlik &&
          !tekrar &&
          e.durum == 401 &&
          e.kod == 'token_suresi_doldu') {
        await _yenile();
        return _gonder(yontem, yol, govde, kimlik, tekrar: true);
      }
      if (kimlik && e.oturumGecersiz) {
        await depo.oturumuTemizle();
        oturumKapandi?.call();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _tekIstek(
    String yontem,
    String yol,
    Map<String, String> basliklar,
    Map<String, dynamic>? govde,
  ) async {
    final uri = Uri.parse('$apiTaban/$yol');
    http.Response r;
    try {
      final istek = http.Request(yontem, uri)..headers.addAll(basliklar);
      if (govde != null) istek.body = jsonEncode(govde);
      r = await http.Response.fromStream(
        await _http.send(istek).timeout(const Duration(seconds: 20)),
      );
    } on TimeoutException {
      throw ApiHata(0, 'zaman_asimi', 'Sunucuya ulaşılamadı (zaman aşımı).');
    } catch (_) {
      throw ApiHata(
        0,
        'ag_yok',
        'İnternet bağlantısı yok ya da sunucuya ulaşılamıyor.',
      );
    }

    return _yanit(r);
  }

  /// {ok,veri|hata} zarfını çözer; hata ise [ApiHata] fırlatır.
  Map<String, dynamic> _yanit(http.Response r) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiHata(
        r.statusCode,
        'yanit_gecersiz',
        'Sunucudan beklenmeyen yanıt geldi (HTTP ${r.statusCode}).',
      );
    }
    if (j['ok'] == true) {
      return (j['veri'] is Map<String, dynamic>)
          ? j['veri'] as Map<String, dynamic>
          : {'veri': j['veri']};
    }
    final h = (j['hata'] as Map?) ?? const {};
    throw ApiHata(
      r.statusCode,
      (h['kod'] ?? 'hata').toString(),
      (h['mesaj'] ?? 'Bir hata oluştu.').toString(),
      h.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  /// İkili içerik indirir (görsel, ek dosya...). Süresi dolan access belirtecini [get]/[post] gibi yeniler.
  /// Dönen `ad`, sunucunun Content-Disposition başlığındaki dosya adıdır (yoksa null).
  Future<({Uint8List bayt, String? ad, String tur})> dosyaIndir(
    String yol, {
    bool tekrar = false,
  }) async {
    final a = await depo.access;
    if (a == null) throw ApiHata(401, 'oturum_gerekli', 'Oturum gerekli.');
    http.Response r;
    try {
      r = await _http
          .get(
            Uri.parse('$apiTaban/$yol'),
            headers: {'Authorization': 'Bearer $a'},
          )
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw ApiHata(
        0,
        'ag_yok',
        'İnternet bağlantısı yok ya da sunucuya ulaşılamıyor.',
      );
    }
    final tur = r.headers['content-type'] ?? '';
    if (r.statusCode == 200 && !tur.contains('application/json')) {
      String? ad;
      final cd = r.headers['content-disposition'];
      final m = cd == null
          ? null
          : RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(cd);
      if (m != null) ad = Uri.decodeComponent(m.group(1)!);
      return (bayt: r.bodyBytes, ad: ad, tur: tur);
    }
    var kod = 'hata';
    var mesaj = 'İndirilemedi (HTTP ${r.statusCode}).';
    try {
      final h = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['hata'] as Map;
      kod = (h['kod'] ?? kod).toString();
      mesaj = (h['mesaj'] ?? mesaj).toString();
    } catch (_) {}
    if (!tekrar && r.statusCode == 401 && kod == 'token_suresi_doldu') {
      await _yenile();
      return dosyaIndir(yol, tekrar: true);
    }
    throw ApiHata(r.statusCode, kod, mesaj);
  }

  /// Görsel gibi ikili içerik indirir (yalnızca baytlar).
  Future<Uint8List> indir(String yol) async => (await dosyaIndir(yol)).bayt;

  /// Çok parçalı (dosya) yükleme: [alanlar] metin alanları, dosya [dosyaAlani] adıyla eklenir.
  Future<Map<String, dynamic>> yukle(
    String yol, {
    required Map<String, String> alanlar,
    required String dosyaAlani,
    required String dosyaYolu,
    required String dosyaAdi,
    bool tekrar = false,
  }) async {
    final a = await depo.access;
    if (a == null) throw ApiHata(401, 'oturum_gerekli', 'Oturum gerekli.');
    final istek = http.MultipartRequest('POST', Uri.parse('$apiTaban/$yol'))
      ..headers['Authorization'] = 'Bearer $a'
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(alanlar)
      ..files.add(
        await http.MultipartFile.fromPath(
          dosyaAlani,
          dosyaYolu,
          filename: dosyaAdi,
        ),
      );
    http.Response r;
    try {
      r = await http.Response.fromStream(
        await _http.send(istek).timeout(const Duration(minutes: 3)),
      );
    } on TimeoutException {
      throw ApiHata(0, 'zaman_asimi', 'Sunucuya ulaşılamadı (zaman aşımı).');
    } catch (_) {
      throw ApiHata(
        0,
        'ag_yok',
        'İnternet bağlantısı yok ya da sunucuya ulaşılamıyor.',
      );
    }
    try {
      return _yanit(r);
    } on ApiHata catch (e) {
      if (!tekrar && e.durum == 401 && e.kod == 'token_suresi_doldu') {
        await _yenile();
        return yukle(
          yol,
          alanlar: alanlar,
          dosyaAlani: dosyaAlani,
          dosyaYolu: dosyaYolu,
          dosyaAdi: dosyaAdi,
          tekrar: true,
        );
      }
      if (e.oturumGecersiz) {
        await depo.oturumuTemizle();
        oturumKapandi?.call();
      }
      rethrow;
    }
  }

  Future<void> _yenile() {
    return _yenileniyor ??= () async {
      try {
        final refresh = await depo.refresh;
        if (refresh == null) {
          throw ApiHata(401, 'oturum_gerekli', 'Oturum gerekli.');
        }
        final v = await _gonder('POST', 'auth/yenile', {
          'refresh_token': refresh,
          'cihaz_kimligi': await depo.cihazKimligi(),
        }, false);
        await depo.belirtecYaz(
          v['access_token'] as String,
          v['refresh_token'] as String,
        );
      } on ApiHata catch (e) {
        // Yenileme 401 ile reddedildiyse oturum bitmiştir; ağ hatasında belirteçler korunur.
        if (e.durum == 401) {
          await depo.oturumuTemizle();
          oturumKapandi?.call();
        }
        rethrow;
      } finally {
        _yenileniyor = null;
      }
    }();
  }
}
