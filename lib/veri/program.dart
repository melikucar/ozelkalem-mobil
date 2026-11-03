import 'dart:convert';

import 'package:flutter/material.dart';

/// Sunucuyla taşınan, kullanıcının düzenleyebildiği program alanları.
const List<String> programAlanlari = [
  'adi',
  'tarih1',
  'tarih2',
  'yer',
  'notlar',
  'renk',
];

const String varsayilanProgramRengi = '#3788d8';

/// Program renk paleti (web'deki renk seçicinin hazır karşılığı).
const List<String> programRenkleri = [
  '#3788d8',
  '#0cabb5',
  '#12a150',
  '#e0a100',
  '#e0701a',
  '#c0182b',
  '#c20060',
  '#8b5cf6',
  '#636e82',
  '#14304e',
];

/// "2026-10-30 14:30:00" / "2026-10-30T14:30" → DateTime; geçersiz ("0000-00-00") ise null.
DateTime? programZamani(Object? v) {
  final d = DateTime.tryParse('$v'.replaceFirst(' ', 'T'));
  return (d == null || d.year < 1900) ? null : d;
}

String _iki(int x) => x.toString().padLeft(2, '0');

/// DateTime → sunucunun beklediği "yyyy-MM-dd HH:mm:ss".
String programZamanYaz(DateTime d) =>
    '${d.year}-${_iki(d.month)}-${_iki(d.day)} ${_iki(d.hour)}:${_iki(d.minute)}:${_iki(d.second)}';

DateTime gunBasi(DateTime d) => DateTime(d.year, d.month, d.day);

bool ayniGun(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Color programRengi(String? hex, [Color yedek = const Color(0xFF3788D8)]) {
  if (hex != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
  return yedek;
}

/// Programın hatırlatıcı ayarı: kaç dakika önce, hangi kanallarla, kimlere.
class HatirlaticiAyar {
  const HatirlaticiAyar({
    this.dakikalar = const [],
    this.uygulama = true,
    this.eposta = false,
    this.sms = false,
    this.smsAlici = 'herkes',
    this.smsKisiler = const [],
    this.epostaAlici = 'herkes',
    this.epostaKisiler = const [],
  });

  final List<int> dakikalar;
  final bool uygulama;
  final bool eposta;
  final bool sms;
  final String smsAlici; // ben | secilen | herkes
  final List<int> smsKisiler;
  final String epostaAlici;
  final List<int> epostaKisiler;

  bool get bos => dakikalar.isEmpty;

  HatirlaticiAyar kopya({
    List<int>? dakikalar,
    bool? uygulama,
    bool? eposta,
    bool? sms,
    String? smsAlici,
    List<int>? smsKisiler,
    String? epostaAlici,
    List<int>? epostaKisiler,
  }) => HatirlaticiAyar(
    dakikalar: dakikalar ?? this.dakikalar,
    uygulama: uygulama ?? this.uygulama,
    eposta: eposta ?? this.eposta,
    sms: sms ?? this.sms,
    smsAlici: smsAlici ?? this.smsAlici,
    smsKisiler: smsKisiler ?? this.smsKisiler,
    epostaAlici: epostaAlici ?? this.epostaAlici,
    epostaKisiler: epostaKisiler ?? this.epostaKisiler,
  );

  /// API ve yerel saklama biçimi.
  Map<String, dynamic> toJson() => {
    'dakikalar': dakikalar,
    'kanal': {
      'uygulama': uygulama ? 1 : 0,
      'eposta': eposta ? 1 : 0,
      'sms': sms ? 1 : 0,
      'sms_alici': smsAlici,
      'sms_kisiler': smsKisiler,
      'eposta_alici': epostaAlici,
      'eposta_kisiler': epostaKisiler,
    },
  };

  factory HatirlaticiAyar.fromJson(Object? j) {
    if (j is! Map) return const HatirlaticiAyar();
    final k = (j['kanal'] is Map) ? j['kanal'] as Map : const {};
    List<int> liste(Object? v) => [
      for (final x in (v as List? ?? const [])) (x as num).toInt(),
    ];
    final dk = liste(j['dakikalar'])..sort();
    return HatirlaticiAyar(
      dakikalar: dk,
      uygulama: k.isEmpty ? true : ((k['uygulama'] as num?)?.toInt() ?? 0) == 1,
      eposta: ((k['eposta'] as num?)?.toInt() ?? 0) == 1,
      sms: ((k['sms'] as num?)?.toInt() ?? 0) == 1,
      smsAlici: (k['sms_alici'] ?? 'herkes').toString(),
      smsKisiler: liste(k['sms_kisiler']),
      epostaAlici: (k['eposta_alici'] ?? 'herkes').toString(),
      epostaKisiler: liste(k['eposta_kisiler']),
    );
  }
}

/// "10 dk önce", "1 saat önce", "2 gün önce" (sunucudaki HatirlatmaServisi::etiket ile aynı).
String hatirlaticiEtiketi(int dakika) {
  if (dakika == 0) return 'Zamanında';
  if (dakika % 10080 == 0) return '${dakika ~/ 10080} hafta önce';
  if (dakika % 1440 == 0) {
    final g = dakika ~/ 1440;
    return '$g gün önce';
  }
  if (dakika % 60 == 0) return '${dakika ~/ 60} saat önce';
  return '$dakika dk önce';
}

/// Yerel veritabanındaki bir program satırı.
class Program {
  Program(this.v);

  final Map<String, Object?> v;

  int? get yerelId => v['yerel_id'] as int?;
  int? get no => v['no'] as int?;
  int get surum => (v['surum'] as int?) ?? 0;
  bool get bekleyen => (v['bekleyen'] as int?) == 1;
  bool get silindi => (v['silindi'] as int?) == 1;

  String s(String k) => (v[k] ?? '').toString();

  String get adi => s('adi');
  String get yer => s('yer');
  String get notlar => s('notlar');
  int get randevuNo => (v['randevu_no'] as int?) ?? 0;
  Color get renk => programRengi(s('renk'));
  String get renkHex => s('renk').isEmpty ? varsayilanProgramRengi : s('renk');

  DateTime get bas => programZamani(v['tarih1']) ?? DateTime.now();

  /// Sunucu bitişi başlangıçtan büyük değilse (eski veri) 1 saatlik varsayılan.
  DateTime get bit {
    final b = programZamani(v['tarih2']);
    return (b != null && b.isAfter(bas))
        ? b
        : bas.add(const Duration(hours: 1));
  }

  /// Bitişi olmayan, gece yarısında başlayan program: takvimde "gün boyu" sayılır.
  bool get tumGun {
    final b = programZamani(v['tarih2']);
    final t = bas;
    return t.hour == 0 && t.minute == 0 && (b == null || !b.isAfter(t));
  }

  HatirlaticiAyar? get hatirlatici {
    final j = v['hat_json'];
    if (j == null || '$j'.isEmpty) return null;
    try {
      return HatirlaticiAyar.fromJson(jsonDecode('$j'));
    } catch (_) {
      return null;
    }
  }

  /// Sunucu yanıtındaki program → yerel sütunlar.
  static Map<String, Object?> apiden(Map<String, dynamic> j) => {
    'no': j['no'],
    'surum': j['surum'] ?? 0,
    'adi': j['adi'],
    'tarih1': j['tarih1'],
    'tarih2': j['tarih2'],
    'yer': j['yer'],
    'notlar': j['notlar'],
    'renk': j['renk'],
    'randevu_no': j['randevu_no'] ?? 0,
    'hat_json': j['hatirlaticilar'] == null
        ? null
        : jsonEncode(j['hatirlaticilar']),
  };
}
