import 'package:flutter/material.dart';

import '../../api/api_istemci.dart';
import '../../api/oturum.dart';
import '../../diger/modul_hero.dart';
import 'ajanda_raporu.dart';
import 'faaliyet_raporu.dart';
import 'talep_raporu.dart';

/// Raporlar: web "Raporlar" modülünün (Talep / Faaliyet / Ajanda istatistik panelleri) mobil karşılığı.
/// İstatistikler sunucuda web ile aynı kurallarla hesaplanır; bu yüzden internet bağlantısı gerekir.
class RaporlarSayfasi extends StatefulWidget {
  const RaporlarSayfasi({super.key, required this.oturum, this.sekme = true});

  final Oturum oturum;
  final bool sekme;

  @override
  State<RaporlarSayfasi> createState() => _RaporlarSayfasiState();
}

class _RaporlarSayfasiState extends State<RaporlarSayfasi> {
  static const _sekmeler = [
    ('Talepler', Icons.assignment_outlined),
    ('Faaliyetler', Icons.campaign_outlined),
    ('Ajanda', Icons.event_note_outlined),
  ];

  int _secili = 0;
  Map<String, dynamic>? _referans;
  String? _hata;

  ApiIstemci get _api => widget.oturum.api;

  @override
  void initState() {
    super.initState();
    _referansYukle();
  }

  Future<void> _referansYukle() async {
    setState(() => _hata = null);
    try {
      final v = await _api.get('raporlar/referans');
      if (mounted) setState(() => _referans = v);
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(
        () => _hata = e.agHatasi
            ? 'Raporlar sunucuda hesaplanır; internet bağlantısı gerekir.'
            : (e.durum == 403 ? 'Raporlar için yetkiniz yok.' : e.mesaj),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final acik = tema.brightness == Brightness.light;
    final zemin = tema.scaffoldBackgroundColor;
    final ust = Color.lerp(zemin, cs.primary, acik ? 0.10 : 0.14)!;
    return Scaffold(
      body: Column(
        children: [
          ModulHero(
            geri: !widget.sekme,
            ikon: Icons.insights_rounded,
            baslik: 'Raporlar',
            altBaslik: '${_sekmeler[_secili].$1} istatistikleri',
            alt: _SekmeSecici(
              secili: _secili,
              degisti: (i) => setState(() => _secili = i),
              sekmeler: _sekmeler,
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ust, zemin, zemin],
                  stops: const [0, 0.2, 1],
                ),
              ),
              child: _referans == null
                  ? (_hata != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cloud_off_rounded,
                                    size: 52,
                                    color: cs.outline,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(_hata!, textAlign: TextAlign.center),
                                  const SizedBox(height: 14),
                                  FilledButton.tonal(
                                    onPressed: _referansYukle,
                                    child: const Text('Tekrar dene'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator()))
                  : IndexedStack(
                      index: _secili,
                      children: [
                        TalepRaporu(api: _api, referans: _referans!),
                        FaaliyetRaporu(api: _api, referans: _referans!),
                        AjandaRaporu(api: _api),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero içindeki rapor türü seçici (koyu zeminde açık renkli hap düğmeler).
class _SekmeSecici extends StatelessWidget {
  const _SekmeSecici({
    required this.secili,
    required this.degisti,
    required this.sekmeler,
  });

  final int secili;
  final ValueChanged<int> degisti;
  final List<(String, IconData)> sekmeler;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          for (var i = 0; i < sekmeler.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == sekmeler.length - 1 ? 0 : 8,
                ),
                child: GestureDetector(
                  onTap: () => degisti(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: i == secili
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sekmeler[i].$2,
                          size: 16,
                          color: i == secili
                              ? const Color(0xFF0C1C2F)
                              : Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            sekmeler[i].$1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: i == secili
                                  ? const Color(0xFF0C1C2F)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
