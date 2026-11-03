/// Liste sıralama seçenekleri (v7 listesiyle aynı).
enum TalepSirala {
  yeni('Yeni → Eski'),
  eski('Eski → Yeni'),
  ad('Ad (A → Z)'),
  kayit('Kayıt sırası');

  const TalepSirala(this.etiket);

  final String etiket;
}

const _yok = Object();

/// Talep listesi için arama + gelişmiş filtre durumu. Değişmezdir; [kopya] ile yenisi üretilir.
class TalepFiltre {
  const TalepFiltre({
    this.arama = '',
    this.durumlar = const {},
    this.kategoriler = const {},
    this.ilce,
    this.kaydeden,
    this.telefon = '',
    this.bas,
    this.bit,
    this.bekleyen = false,
    this.hatirlatici = false,
    this.sirala = TalepSirala.yeni,
  });

  final String arama;
  final Set<int> durumlar;
  final Set<int> kategoriler;
  final int? ilce;
  final int? kaydeden;

  /// Yalnızca rakamlar da yazılabilir: "532 12" gibi.
  final String telefon;

  /// "2026-10-30" biçiminde, uçlar dahil.
  final String? bas;
  final String? bit;
  final bool bekleyen;
  final bool hatirlatici;
  final TalepSirala sirala;

  TalepFiltre kopya({
    String? arama,
    Set<int>? durumlar,
    Set<int>? kategoriler,
    Object? ilce = _yok,
    Object? kaydeden = _yok,
    String? telefon,
    Object? bas = _yok,
    Object? bit = _yok,
    bool? bekleyen,
    bool? hatirlatici,
    TalepSirala? sirala,
  }) => TalepFiltre(
    arama: arama ?? this.arama,
    durumlar: durumlar ?? this.durumlar,
    kategoriler: kategoriler ?? this.kategoriler,
    ilce: identical(ilce, _yok) ? this.ilce : ilce as int?,
    kaydeden: identical(kaydeden, _yok) ? this.kaydeden : kaydeden as int?,
    telefon: telefon ?? this.telefon,
    bas: identical(bas, _yok) ? this.bas : bas as String?,
    bit: identical(bit, _yok) ? this.bit : bit as String?,
    bekleyen: bekleyen ?? this.bekleyen,
    hatirlatici: hatirlatici ?? this.hatirlatici,
    sirala: sirala ?? this.sirala,
  );

  /// Gelişmiş panelde ayarlanmış filtre sayısı (arama, durum çipleri ve sıralama dahil değil).
  int get panelSayisi =>
      (kategoriler.isNotEmpty ? 1 : 0) +
      (ilce != null ? 1 : 0) +
      (kaydeden != null ? 1 : 0) +
      (telefon.trim().isNotEmpty ? 1 : 0) +
      (bas != null || bit != null ? 1 : 0) +
      (bekleyen ? 1 : 0) +
      (hatirlatici ? 1 : 0);

  /// Arama dahil herhangi bir daraltma var mı (sıralama sayılmaz).
  bool get daraltiyor =>
      arama.trim().isNotEmpty || durumlar.isNotEmpty || panelSayisi > 0;

  /// Arama ve durum dışındaki tüm filtreleri ve sıralamayı bırakır; arama/durum korunur.
  TalepFiltre panelTemiz() =>
      TalepFiltre(arama: arama, durumlar: durumlar, sirala: sirala);
}
