import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Belirteçler ve cihaz kimliği, işletim sisteminin güvenli deposunda (Android Keystore / iOS Keychain) tutulur.
class TokenDeposu {
  TokenDeposu([FlutterSecureStorage? depo])
    : _depo = depo ?? const FlutterSecureStorage();

  final FlutterSecureStorage _depo;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kCihaz = 'cihaz_kimligi';
  static const _kBen = 'ben_onbellek';

  Future<String?> get access => _depo.read(key: _kAccess);
  Future<String?> get refresh => _depo.read(key: _kRefresh);

  /// İlk açılışta üretilen, sonraki girişlerde de sabit kalan cihaz kimliği.
  Future<String> cihazKimligi() async {
    var id = await _depo.read(key: _kCihaz);
    if (id == null || id.length < 8) {
      id = const Uuid().v4();
      await _depo.write(key: _kCihaz, value: id);
    }
    return id;
  }

  Future<void> belirtecYaz(String access, String refresh) async {
    await _depo.write(key: _kAccess, value: access);
    await _depo.write(key: _kRefresh, value: refresh);
  }

  Future<bool> get oturumVar async => (await refresh) != null;

  Future<void> benYaz(Map<String, dynamic> ben) =>
      _depo.write(key: _kBen, value: jsonEncode(ben));

  Future<Map<String, dynamic>?> benOku() async {
    final s = await _depo.read(key: _kBen);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Makam görseli / profil fotoğrafı gibi indirilen görseller: [ad] ile ayrılır, [ozet] sunucudaki sürümü gösterir.
  Future<void> gorselYaz(String ad, String ozet, Uint8List bayt) async {
    await _depo.write(key: 'gorsel_${ad}_ozet', value: ozet);
    await _depo.write(key: 'gorsel_$ad', value: base64Encode(bayt));
  }

  Future<({String ozet, Uint8List bayt})?> gorselOku(String ad) async {
    final o = await _depo.read(key: 'gorsel_${ad}_ozet');
    final b = await _depo.read(key: 'gorsel_$ad');
    if (o == null || b == null) return null;
    try {
      return (ozet: o, bayt: base64Decode(b));
    } catch (_) {
      return null;
    }
  }

  Future<void> gorselSil(String ad) async {
    await _depo.delete(key: 'gorsel_${ad}_ozet');
    await _depo.delete(key: 'gorsel_$ad');
  }

  /// Çıkışta belirteçleri ve önbelleği siler; cihaz kimliği korunur.
  Future<void> oturumuTemizle() async {
    await _depo.delete(key: _kAccess);
    await _depo.delete(key: _kRefresh);
    await _depo.delete(key: _kBen);
    await gorselSil('makam');
    await gorselSil('profil');
  }
}
