import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_istemci.dart';
import '../api/oturum.dart';
import '../veri/talep_filtre.dart';
import '../tema/tema.dart';
import '../veri/veri_katmani.dart';
import 'ana_arama.dart';
import 'ana_bloklar.dart';
import '../veri/genel_arama.dart';
import 'marka_bilesenleri.dart';
import 'modul_hero.dart';
import '../moduller/talepler/talep_detay.dart';
import '../moduller/faaliyetler/faaliyet_detay.dart';
import '../moduller/randevular/randevu_detay.dart';
import '../moduller/programlar/program_detay.dart';
import 'cekince_esitle.dart';

/// Ana sayfa: kompakt lacivert başlık (logo + makam bilgisi, eşitleme durumu) ve web ana sayfasındaki blokların mobil karşılığı:
/// dikey rakamlar, talep hatırlatıcı, beklemede olan talepler, son faaliyetler, telefon görüşmeleri.
/// Veri sunucudan gelir (anasayfa/ozet), son başarılı yanıt cihazda saklanır; bağlantı yokken o gösterilir.
class AnaSayfa extends StatefulWidget {
  const AnaSayfa({
    super.key,
    required this.oturum,
    required this.veri,
    required this.git,
    required this.durumGit,
    this.profilAc,
  });

  final Oturum oturum;
  final VeriKatmani veri;

  /// Alt gezinti sekmesine geç (modül anahtarı).
  final void Function(String modul) git;

  /// Talepler sekmesini verilen durum numarasıyla süzülmüş açar.
  final void Function(int durumNo) durumGit;

  /// Hero'daki küçük profil resmine dokununca hesap menüsünü açar (resmin ekran dikdörtgeniyle).
  final void Function(Rect kaynak)? profilAc;

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  Map<String, dynamic>? _ozet;
  bool _yukleniyor = true;
  bool _hata = false;
  String _hataAyrinti = '';
  Map<String, dynamic>? _yerel; // sunucu özeti alınamadıysa cihazdaki taleplerden üretilen yedek rakamlar

  Oturum get oturum => widget.oturum;
  VeriKatmani get veri => widget.veri;

  @override
  void initState() {
    super.initState();
    veri.motor.addListener(_motorDegisti);
    _onbellektenAc();
    _yukle();
  }

  @override
  void dispose() {
    veri.motor.removeListener(_motorDegisti);
    _esitZaman?.cancel();
    _cekme.dispose();
    _kayma.dispose();
    super.dispose();
  }

  bool _eskiCalisiyor = false;
  bool _manuel =
      false; // aşağı çekerek istenen eşitleme: sonucu göstergede gösterilir
  EsitlemeDurumu _esitDurum = EsitlemeDurumu.bos;
  String _bitisMetni = 'Tüm veriler sistemle eşitlendi';
  Timer? _esitZaman;
  final ValueNotifier<double> _cekme = ValueNotifier(0);
  final ValueNotifier<double> _kayma = ValueNotifier(
    0,
  ); // içeriğin piksel olarak aşağı inişi
  double _asiri = 0;
  bool _tetiklendi = false;
  final _aramaAnahtar = GlobalKey<AnaAramaState>();
  bool _aramaAktif = false; // sonuç alanı açık: çevre bulanıklaşır

  /// Sayfa en üstteyken aşağı çekmek: rozet çekilen kadar iner, yeterince çekilince eşitleme başlar.
  bool _kaydirma(ScrollNotification n) {
    if (_esitDurum != EsitlemeDurumu.bos)
      return false; // gösterge açık: kapanana dek dokunulmaz
    if (n is OverscrollNotification && n.overscroll < 0) {
      if (_asiri == 0) HapticFeedback.lightImpact(); // çekme başladı
      _asiri = (_asiri - n.overscroll).clamp(0, 140);
      _cekme.value = (_asiri / 40).clamp(0, 1);
      _kayma.value = cekmeKaymasi(_asiri);
      if (_asiri >= 40 && !_tetiklendi) {
        _tetiklendi = true;
        HapticFeedback.mediumImpact(); // eşik aşıldı: eşitleme başlıyor
        titret();
        _manuel = true;
        _kayma.value = EsitlemeGostergesi.yukseklik; // gösterge açık kalır
        setState(() => _esitDurum = EsitlemeDurumu.esitleniyor);
        veri.motor.elleSenkronla();
        if (!_yukleniyor) _yukle();
      }
    } else if (n is ScrollEndNotification ||
        (n is ScrollUpdateNotification && n.metrics.pixels > 0)) {
      _asiri = 0;
      _tetiklendi = false;
      _cekme.value = 0;
      _kayma.value = 0;
    }
    return false;
  }

  /// Her eşitleme bittiğinde (rozete dokunma dahil) ana sayfa blokları da tazelenir.
  void _motorDegisti() {
    final c = veri.motor.calisiyor;
    final bitti = _eskiCalisiyor && !c;
    _eskiCalisiyor = c;
    if (bitti && _manuel) _esitSonucu();
    if (bitti && !_yukleniyor) {
      _yukle();
      oturum.benYukle();
    }
  }

  Future<void> _esitSonucu() async {
    _manuel = false;
    int? n;
    try {
      n = await veri.motor.kayitSayaci?.call();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _bitisMetni = esitlendiMetni(n);
      _esitDurum = veri.motor.cevrimdisi
          ? EsitlemeDurumu.cevrimdisi
          : EsitlemeDurumu.tamam;
    });
    _esitZaman?.cancel();
    _esitZaman = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _esitDurum = EsitlemeDurumu.bos);
      _asiri = 0;
      _tetiklendi = false;
      _cekme.value = 0;
      _kayma.value = 0;
    });
  }

  Future<void> _onbellektenAc() async {
    final j = await veri.talepler.meta('ana_ozet');
    if (j == null || !mounted || _ozet != null) return;
    try {
      setState(() => _ozet = jsonDecode(j) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _yukle() async {
    _yukleniyor = true;
    try {
      _hata = false;
      final v = await veri.motor.api.get('anasayfa/ozet');
      if (!mounted) return; // çıkış yapılmış olabilir: veritabanı kapanmıştır
      await veri.talepler.metaYaz('ana_ozet', jsonEncode(v));
      if (mounted) setState(() => _ozet = v);
    } on ApiHata catch (e) {
      _hataAyrinti = e.agHatasi
          ? 'Sunucuya ulaşılamıyor (bağlantı yok).'
          : 'Sunucu yanıtı: ${e.durum} ${e.kod} — ${e.mesaj}';
      // çevrimdışı ya da sunucu henüz güncel değil: saklı özet gösterilir; yoksa cihazdaki taleplerden rakamlar üretilir
      _hata = true;
      await _yerelRakamlar();
    } catch (_) {
      // ekran kapanırken biten istekler sessizce bırakılır
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// Sunucu özeti gelmediğinde bile ana sayfa boş kalmasın: cihazdaki talepler üzerinden toplam/bugün/dün.
  Future<void> _yerelRakamlar() async {
    if (!oturum.modulVar('talepler')) return;
    try {
      final d = veri.talepler;
      String iso(DateTime t) =>
          '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      final n = DateTime.now();
      final bugun = iso(n);
      final dun = iso(n.subtract(const Duration(days: 1)));
      final r = {
        'toplam_talep': await d.sayi(),
        'bugun': await d.sonucSayisi(TalepFiltre(bas: bugun, bit: bugun)),
        'dun': await d.sonucSayisi(TalepFiltre(bas: dun, bit: dun)),
      };
      if (mounted) setState(() => _yerel = r);
    } catch (_) {}
  }

  void _inmediUyar(String ne) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Bu $ne cihaza henüz inmedi; eşitleme bitince açılır.'),
      ),
    );

  Future<void> _faaliyetAc(int no) async {
    final id = await veri.faaliyetler.yerelIdNo(no);
    if (!mounted) return;
    if (id == null) return _inmediUyar('faaliyet');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaaliyetDetay(veri: veri, yerelId: id),
      ),
    );
  }

  Future<void> _randevuAc(int no) async {
    final id = await veri.randevular.yerelIdNo(no);
    if (!mounted) return;
    if (id == null) return _inmediUyar('randevu');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RandevuDetay(veri: veri, yerelId: id),
      ),
    );
  }

  Future<void> _programAc(int no) async {
    final id = await veri.programlar.yerelIdNo(no);
    if (!mounted) return;
    if (id == null) return _inmediUyar('program');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgramDetay(veri: veri, yerelId: id),
      ),
    );
  }

  Future<void> _talepAc(int no) async {
    final id = await veri.talepler.yerelIdNo(no);
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Bu talep cihaza henüz inmedi; eşitleme bitince açılır.',
            ),
          ),
        );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TalepDetay(veri: veri, yerelId: id),
      ),
    );
  }

  Map<String, dynamic>? _bolum(String ad) {
    final v = _ozet?[ad];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(body: _icerik(context)),
    );
  }

  Widget _icerik(BuildContext context) {
    final rakamlar = _bolum('rakamlar') ?? _yerel;
    final hatirlatici = _bolum('hatirlaticilar');
    final bekleyen = _bolum('bekleyenler');
    final durumlar = _bolum('durumlar');
    final takvim = _bolum('takvim');
    final randevu = _bolum('randevular');
    final faaliyet = _bolum('faaliyetler');
    final gorusme = _bolum('gorusmeler');
    final bos =
        rakamlar == null &&
        hatirlatici == null &&
        bekleyen == null &&
        durumlar == null &&
        takvim == null &&
        randevu == null &&
        faaliyet == null &&
        gorusme == null;
    return LayoutBuilder(
      builder: (context, k) {
        final genislik = k.maxWidth > 760 ? 760.0 : k.maxWidth;
        final yan = (k.maxWidth - genislik) / 2 + 16;
        return NotificationListener<ScrollNotification>(
          onNotification: _kaydirma,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              ListenableBuilder(
                listenable: oturum,
                builder: (context, _) => _Bulanik(
                  aktif: _aramaAktif,
                  kapat: () => _aramaAnahtar.currentState?.kapat(),
                  child: _Hero(
                    oturum: oturum,
                    veri: veri,
                    profilAc: widget.profilAc,
                  ),
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _kayma,
                // Eşitleme göstergesi hero'nun hemen altında (içeriğin üstünde), diğer modüllerdeki gibi açılır
                builder: (c, k, ch) => Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: EsitlemeGostergesi.yukseklik,
                      child: EsitlemeGostergesi(
                        durum: _esitDurum,
                        kayma: k,
                        bitisMetni: _bitisMetni,
                      ),
                    ),
                    CekmeKaydirici(kayma: k, child: ch!),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(yan, 16, yan, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (GenelArama.aranabilir(oturum.modulVar))
                        AnaArama(
                          key: _aramaAnahtar,
                          oturum: oturum,
                          veri: veri,
                          sonucDegisti: (a) {
                            if (mounted) setState(() => _aramaAktif = a);
                          },
                        ),
                      _Bulanik(
                        aktif: _aramaAktif,
                        kapat: () => _aramaAnahtar.currentState?.kapat(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bos && _yukleniyor)
                              const BlokIskeleti()
                            else if (bos &&
                                !oturum.modulVar('talepler') &&
                                !_hata)
                              const _BosDurum()
                            else if (bos)
                              _YuklenemediKutusu(
                                tekrar: _yukle,
                                ayrinti: _hataAyrinti,
                              )
                            else ...[
                              if (rakamlar != null)
                                RakamlarKarti(
                                  git: widget.git,
                                  modulVar: oturum.modulVar,
                                  veri: rakamlar,
                                  talepGit: oturum.modulVar('talepler')
                                      ? () => widget.git('talepler')
                                      : null,
                                ),
                              if (durumlar != null)
                                DurumlarBlok(
                                  veri: durumlar,
                                  ac: widget.durumGit,
                                ),
                              if (takvim != null)
                                TakvimBlok(veri: takvim, ac: _programAc),
                              if (randevu != null)
                                RandevularBlok(
                                  veri: randevu,
                                  hepsi: () => widget.git('randevular'),
                                  ac: _randevuAc,
                                ),
                              if (hatirlatici != null)
                                HatirlaticiBlok(
                                  veri: hatirlatici,
                                  ac: _talepAc,
                                ),
                              if (bekleyen != null)
                                BekleyenBlok(
                                  veri: bekleyen,
                                  ac: _talepAc,
                                  hepsi: () => widget.git('talepler'),
                                ),
                              if (faaliyet != null)
                                FaaliyetBlok(
                                  veri: faaliyet,
                                  api: veri.motor.api,
                                  hepsi: () => widget.git('faaliyetler'),
                                  ac: _faaliyetAc,
                                ),
                              if (gorusme != null)
                                GorusmeBlok(
                                  veri: gorusme,
                                  hepsi: () => widget.git('telefonlar'),
                                ),
                              if (_hata && _ozet == null)
                                _YuklenemediKutusu(
                                  tekrar: _yukle,
                                  ayrinti: _hataAyrinti,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ana sayfa hero'sunun sağında küçük, yuvarlak profil resmi: dokununca hesap menüsü (aşağı doğru) açılır.
/// Ana sayfada arama sonucu açıkken çevreyi bulanıklaştırıp hafifçe karartır (Modüller baloncukları açılırken olduğu gibi);
/// bulanık alana dokununca arama kapanır. [aktif] false iken hiçbir etkisi ve maliyeti yoktur.
class _Bulanik extends StatelessWidget {
  const _Bulanik({
    required this.aktif,
    required this.kapat,
    required this.child,
  });

  final bool aktif;
  final VoidCallback kapat;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: aktif ? 1.0 : 0.0),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, t, ch) => Stack(
      children: [
        ImageFiltered(
          enabled: t > 0,
          imageFilter: ImageFilter.blur(
            sigmaX: 6 * t,
            sigmaY: 6 * t,
            tileMode: TileMode.decal,
          ),
          child: ch!,
        ),
        if (t > 0)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !aktif,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: kapat,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.16 * t),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _KucukProfil extends StatelessWidget {
  const _KucukProfil({required this.foto, required this.tikla});

  final Uint8List? foto;
  final void Function(Rect kaynak) tikla;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Profil',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        final kutu = context.findRenderObject() as RenderBox;
        tikla(kutu.localToGlobal(Offset.zero) & kutu.size);
      },
      // Çerçeve (border) resmin ÜSTÜNE taşmasın: resim, çerçeve kalınlığı kadar içeride ve ayrıca yuvarlak kırpılır
      child: Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(1.6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.65),
            width: 1.4,
          ),
        ),
        child: ClipOval(
          child: foto == null
              ? const Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                )
              : Image.memory(
                  foto!,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.oturum, required this.veri, this.profilAc});

  final Oturum oturum;
  final VeriKatmani veri;
  final void Function(Rect kaynak)? profilAc;

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.paddingOf(context).top;
    final tema = Theme.of(context);
    final m = (oturum.ben?['makam'] as Map?) ?? const {};
    final ad = (m['adi'] ?? 'Makam').toString();
    final satirlar = [m['unvan']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .map((e) => e.toString())
        .toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Marka.lacivert, Marka.lacivert2],
        ),
        boxShadow: [
          BoxShadow(
            color: Marka.lacivert.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Marka dokusu: gradyan ışıltılar ve köşede çok silik logo işareti
          const HeroDokusu(isaretBoyu: 230),
          Padding(
            padding: EdgeInsets.fromLTRB(16, ust + 10, 6, 14),
            child: BeyazIkonlar(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MakamAvatari(
                          resim: oturum.makamResmi,
                          ad: ad,
                          boyut: 46,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ad,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                  height: 1.15,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              if (satirlar.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text(
                                    satirlar.join(' · '),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFFC3CFDE),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (profilAc != null) ...[
                          const SizedBox(width: 8),
                          _KucukProfil(
                            foto: oturum.profilFoto,
                            tikla: profilAc!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Kullanıcının vurgu rengiyle ince çizgi: hero ile temayı bağlar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    tema.colorScheme.primary,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eşitleme sürerken rozetteki dönen simge.
class _DonenSimge extends StatefulWidget {
  const _DonenSimge({required this.renk});

  final Color renk;

  @override
  State<_DonenSimge> createState() => _DonenSimgeState();
}

class _DonenSimgeState extends State<_DonenSimge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _c,
    child: Icon(Icons.sync_rounded, size: 14, color: widget.renk),
  );
}

/// Çıkış: gönderilmemiş değişiklik varsa uyarır; onaylanırsa açık ekranlar kapatılır, oturum sonlanır ve yerel veri silinir.
Future<void> hesaptanCik(
  BuildContext context,
  Oturum oturum,
  VeriKatmani veri,
) async {
  final bekleyen = await veri.talepler.kuyrukSayisi();
  if (!context.mounted) return;
  final onay = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Çıkış yapılsın mı?'),
      content: Text(
        bekleyen > 0
            ? 'Sunucuya gönderilmemiş $bekleyen değişiklik var. Çıkarsanız bu değişiklikler SİLİNİR. '
                  'Önce bağlantı kurup eşitlemeniz önerilir.'
            : 'Bu cihazdaki yerel veriler silinir; tekrar girişte sunucudan yeniden indirilir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(bekleyen > 0 ? 'Yine de çık' : 'Çık'),
        ),
      ],
    ),
  );
  if (onay != true) return;
  if (!context.mounted) return;
  // Üstte açık ekran (profil, ayrıntı...) varsa kapatılır; sonra oturum kapanır, veri katmanı ekranın kapanışında silme isteğiyle kapatılır:
  // ekranlar hâlâ açıkken veritabanını kapatmak hata verir.
  Navigator.of(context).popUntil((r) => r.isFirst);
  veri.silinecek = true;
  await oturum.cikis();
}

/// Ana sayfa blokları sunucudan alınamadığında: nedenini söyler, yeniden denemeye izin verir.
class _YuklenemediKutusu extends StatelessWidget {
  const _YuklenemediKutusu({required this.tekrar, this.ayrinti = ''});

  final VoidCallback tekrar;

  /// Sorunun ne olduğunu gösteren kısa teknik not (destek için).
  final String ayrinti;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tema.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ana sayfa bilgileri şu an alınamadı.',
                  style: tema.textTheme.bodyMedium,
                ),
                if (ayrinti.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      ayrinti,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(onPressed: tekrar, child: const Text('Yenile')),
        ],
      ),
    );
  }
}

/// Hiçbir modüle yetkisi olmayan kullanıcı için.
class _BosDurum extends StatelessWidget {
  const _BosDurum();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Text(
        'Hesabınıza tanımlı bir modül yok. Yetki için sistem yöneticinizle görüşün.',
      ),
    ),
  );
}

/// Başlıktaki hesap düğmesi: profil fotoğrafı varsa yuvarlak fotoğraf, yoksa hesap simgesi.
