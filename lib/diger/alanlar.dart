import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Web formundaki "0(999) 999 99 99" maskesi: yalnızca rakam alır, baştaki 0 yok sayılır, en çok 10 hane (5xx...).
String telefonBicimle(String ham) {
  var d = ham.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('90') && d.length > 10) d = d.substring(2);
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length > 10) d = d.substring(0, 10);
  if (d.isEmpty) return '';
  final b = StringBuffer('0(');
  b.write(d.substring(0, d.length < 3 ? d.length : 3));
  if (d.length >= 3) b.write(')');
  if (d.length > 3) b.write(' ${d.substring(3, d.length < 6 ? d.length : 6)}');
  if (d.length > 6) b.write(' ${d.substring(6, d.length < 8 ? d.length : 8)}');
  if (d.length > 8) b.write(' ${d.substring(8)}');
  return b.toString();
}

/// Telefon biçimlenmiş mi ve tam mı (10 hane)?
bool telefonTam(String metin) =>
    metin
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0'), '')
        .length ==
    10;

class TelefonMaskesi extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue eski,
    TextEditingValue yeni,
  ) {
    final metin = telefonBicimle(yeni.text);
    return TextEditingValue(
      text: metin,
      selection: TextSelection.collapsed(offset: metin.length),
    );
  }
}

class SecimOgesi<T> {
  const SecimOgesi(this.deger, this.ad);

  final T deger;
  final String ad;
}

/// Aranabilir seçim alanı: dokununca arama kutulu bir liste açılır (il/ilçe/semt/mahalle gibi uzun listeler için).
/// Liste yüklenemezse (ağ yok, daha önce indirilmemiş) sebebi söyler ve tekrar denemeye izin verir.
class SecimAlani<T> extends FormField<T> {
  SecimAlani({
    super.key,
    required String etiket,
    required IconData ikon,
    required Future<List<SecimOgesi<T>>> Function() liste,
    required ValueChanged<T?> degisti,
    super.initialValue,
    super.validator,
    bool etkin = true,
    String bos = 'Seçiniz',
    bool temizlenebilir = true,
    String? gorunenAd,
  }) : super(
         enabled: etkin,
         builder: (state) {
           final context = state.context;
           final tema = Theme.of(context);
           final hata = state.errorText;
           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               InkWell(
                 borderRadius: BorderRadius.circular(12),
                 onTap: !etkin
                     ? null
                     : () async {
                         final secilen =
                             await showModalBottomSheet<_SecimSonucu<T>>(
                               context: context,
                               isScrollControlled: true,
                               builder: (_) => _SecimSayfasi<T>(
                                 baslik: etiket,
                                 liste: liste,
                                 secili: state.value,
                                 temizlenebilir: temizlenebilir,
                               ),
                             );
                         if (secilen != null) {
                           state.didChange(secilen.deger);
                           degisti(secilen.deger);
                         }
                       },
                 child: InputDecorator(
                   isEmpty: state.value == null,
                   decoration: InputDecoration(
                     labelText: etiket,
                     floatingLabelBehavior: FloatingLabelBehavior.always,
                     prefixIcon: Icon(ikon),
                     suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                     errorText: hata,
                     enabled: etkin,
                   ),
                   child: Text(
                     state.value == null
                         ? bos
                         : (gorunenAd ?? '${state.value}'),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                     style: TextStyle(
                       color: state.value == null
                           ? tema.colorScheme.onSurfaceVariant
                           : tema.colorScheme.onSurface,
                     ),
                   ),
                 ),
               ),
             ],
           );
         },
       );
}

class _SecimSonucu<T> {
  const _SecimSonucu(this.deger);

  final T? deger;
}

class _SecimSayfasi<T> extends StatefulWidget {
  const _SecimSayfasi({
    required this.baslik,
    required this.liste,
    required this.secili,
    required this.temizlenebilir,
  });

  final String baslik;
  final Future<List<SecimOgesi<T>>> Function() liste;
  final T? secili;
  final bool temizlenebilir;

  @override
  State<_SecimSayfasi<T>> createState() => _SecimSayfasiState<T>();
}

class _SecimSayfasiState<T> extends State<_SecimSayfasi<T>> {
  late Future<List<SecimOgesi<T>>> _yukle = widget.liste();
  String _ara = '';

  String _kat(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final yuk = MediaQuery.sizeOf(context).height * 0.78;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: yuk,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.baslik,
                      style: tema.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.temizlenebilir && widget.secili != null)
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, _SecimSonucu<T>(null)),
                      child: const Text('Temizle'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _ara = _kat(v.trim())),
                decoration: const InputDecoration(
                  hintText: 'Ara',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<SecimOgesi<T>>>(
                future: _yukle,
                builder: (context, s) {
                  if (s.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (s.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, size: 40),
                            const SizedBox(height: 12),
                            const Text(
                              'Liste indirilemedi. Bu liste daha önce cihaza alınmadıysa bağlantı gerekir.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _yukle = widget.liste()),
                              child: const Text('Tekrar dene'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final tum = s.data ?? [];
                  final liste = _ara.isEmpty
                      ? tum
                      : tum.where((o) => _kat(o.ad).contains(_ara)).toList();
                  if (liste.isEmpty) {
                    return Center(
                      child: Text(tum.isEmpty ? 'Bu liste boş.' : 'Sonuç yok.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: liste.length,
                    itemBuilder: (context, i) {
                      final o = liste[i];
                      final secili = o.deger == widget.secili;
                      return ListTile(
                        title: Text(o.ad),
                        trailing: secili
                            ? Icon(
                                Icons.check_rounded,
                                color: tema.colorScheme.primary,
                              )
                            : null,
                        selected: secili,
                        onTap: () =>
                            Navigator.pop(context, _SecimSonucu<T>(o.deger)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yazarken öneri açan metin alanı (rehberden kişi, geçmiş referanslar, kurumlar). Öneriler gecikmeli aranır ve ağ hatasında sessizce atlanır.
class OneriAlani<T extends Object> extends StatefulWidget {
  const OneriAlani({
    super.key,
    required this.controller,
    required this.etiket,
    required this.ikon,
    required this.oneriler,
    required this.metin,
    required this.sec,
    this.altMetin,
    this.validator,
    this.klavye,
    this.buyukHarf = false,
    this.degisti,
    this.etkin = true,
    this.minKarakter = 3,
  });

  final TextEditingController controller;
  final String etiket;
  final IconData ikon;
  final Future<List<T>> Function(String kelime) oneriler;
  final String Function(T) metin;
  final String? Function(T)? altMetin;
  final void Function(T) sec;
  final FormFieldValidator<String>? validator;
  final TextInputType? klavye;
  final bool buyukHarf;
  final ValueChanged<String>? degisti;
  final bool etkin;
  final int minKarakter;

  @override
  State<OneriAlani<T>> createState() => _OneriAlaniState<T>();
}

class _OneriAlaniState<T extends Object> extends State<OneriAlani<T>> {
  final _odak = FocusNode();
  String _son = '';

  @override
  void dispose() {
    _odak.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<T>(
      textEditingController: widget.controller,
      focusNode: _odak,
      displayStringForOption: widget.metin,
      optionsBuilder: (v) async {
        final q = v.text.trim();
        _son = q;
        if (q.length < widget.minKarakter) return Iterable<T>.empty();
        await Future.delayed(const Duration(milliseconds: 320));
        if (_son != q) {
          return Iterable<T>.empty(); // kullanıcı yazmaya devam etti
        }
        try {
          return await widget.oneriler(q);
        } catch (_) {
          return Iterable<T>.empty();
        }
      },
      onSelected: widget.sec,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            enabled: widget.etkin,
            keyboardType: widget.klavye,
            textCapitalization: widget.buyukHarf
                ? TextCapitalization.characters
                : TextCapitalization.none,
            decoration: InputDecoration(
              labelText: widget.etiket,
              prefixIcon: Icon(widget.ikon),
            ),
            validator: widget.validator,
            onChanged: widget.degisti,
            onFieldSubmitted: (_) => onSubmit(),
          ),
      optionsViewBuilder: (context, secildi, secenekler) {
        final tema = Theme.of(context);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: tema.colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 260,
                maxWidth: MediaQuery.sizeOf(context).width - 56,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: secenekler.length,
                itemBuilder: (context, i) {
                  final o = secenekler.elementAt(i);
                  final alt = widget.altMetin?.call(o);
                  return ListTile(
                    dense: true,
                    title: Text(
                      widget.metin(o),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: alt == null || alt.isEmpty ? null : Text(alt),
                    onTap: () => secildi(o),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
