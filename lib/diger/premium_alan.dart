import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/tema.dart';

/// Giriş formunun metin alanı: üstte etiket, solda simge plakası, odaklanınca altın ışıma, altında hata metni.
/// [FormField] olduğu için Form.validate() ile çalışır; değeri controller'dan okur.
class PremiumAlan extends FormField<String> {
  PremiumAlan({
    super.key,
    required TextEditingController controller,
    required String etiket,
    required IconData ikon,
    String? ipucu,
    super.validator,
    TextInputType? klavye,
    TextInputAction? eylem,
    bool gizli = false,
    List<TextInputFormatter>? bicim,
    Iterable<String>? otomatik,
    ValueChanged<String>? gonderildi,
    bool etkin = true,
    FocusNode? odak,
    Widget Function(BuildContext context, String metin)? sonEk,
  }) : super(
         initialValue: controller.text,
         enabled: etkin,
         builder: (state) => _AlanGorunumu(
           state: state,
           controller: controller,
           etiket: etiket,
           ikon: ikon,
           ipucu: ipucu,
           klavye: klavye,
           eylem: eylem,
           gizli: gizli,
           bicim: bicim,
           otomatik: otomatik,
           gonderildi: gonderildi,
           etkin: etkin,
           odak: odak,
           sonEk: sonEk,
         ),
       );
}

class _AlanGorunumu extends StatefulWidget {
  const _AlanGorunumu({
    required this.state,
    required this.controller,
    required this.etiket,
    required this.ikon,
    required this.ipucu,
    required this.klavye,
    required this.eylem,
    required this.gizli,
    required this.bicim,
    required this.otomatik,
    required this.gonderildi,
    required this.etkin,
    required this.odak,
    required this.sonEk,
  });

  final FormFieldState<String> state;
  final TextEditingController controller;
  final String etiket;
  final IconData ikon;
  final String? ipucu;
  final TextInputType? klavye;
  final TextInputAction? eylem;
  final bool gizli;
  final List<TextInputFormatter>? bicim;
  final Iterable<String>? otomatik;
  final ValueChanged<String>? gonderildi;
  final bool etkin;
  final FocusNode? odak;
  final Widget Function(BuildContext, String)? sonEk;

  @override
  State<_AlanGorunumu> createState() => _AlanGorunumuState();
}

class _AlanGorunumuState extends State<_AlanGorunumu> {
  late final FocusNode _odak = widget.odak ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _odak.addListener(_yenile);
    widget.controller.addListener(_metin);
  }

  @override
  void dispose() {
    _odak.removeListener(_yenile);
    widget.controller.removeListener(_metin);
    if (widget.odak == null) _odak.dispose();
    super.dispose();
  }

  void _yenile() => setState(() {});

  void _metin() {
    // FormField değeri güncel kalsın; yazarken hata mesajı kalkar
    if (widget.state.value != widget.controller.text) {
      widget.state.didChange(widget.controller.text);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final odakta = _odak.hasFocus;
    final hata = widget.state.errorText;
    final kenar = hata != null
        ? const Color(0xFFD92D20)
        : (odakta ? Marka.altinKoyu : const Color(0xFFD0D7E1));
    final kapali = !widget.etkin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            widget.etiket,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2A3747),
              letterSpacing: -0.1,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: kapali ? const Color(0xFFF0F2F5) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: kenar,
              width: odakta || hata != null ? 1.8 : 1.2,
            ),
            boxShadow: [
              if (odakta && hata == null)
                BoxShadow(
                  color: Marka.altinKoyu.withValues(alpha: 0.24),
                  blurRadius: 16,
                  spreadRadius: 1,
                )
              else
                BoxShadow(
                  color: Marka.lacivert.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(8),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: odakta
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Marka.altin, Marka.altinKoyu],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFEEF2F7), Color(0xFFE4EAF2)],
                        ),
                ),
                child: Icon(
                  widget.ikon,
                  size: 21,
                  color: odakta ? Marka.lacivert : const Color(0xFF5E6D80),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _odak,
                  enabled: widget.etkin,
                  obscureText: widget.gizli,
                  keyboardType: widget.klavye,
                  textInputAction: widget.eylem,
                  inputFormatters: widget.bicim,
                  autofillHints: widget.otomatik,
                  onSubmitted: widget.gonderildi,
                  cursorColor: Marka.altinKoyu,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF14202E),
                    letterSpacing: 0,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.ipucu,
                    hintStyle: const TextStyle(
                      color: Color(0xFF9AA5B4),
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
              if (widget.sonEk != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: widget.sonEk!(context, widget.controller.text),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topLeft,
          child: hata == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: 4, top: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 15,
                        color: Color(0xFFD92D20),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          hata,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFFB42318),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
