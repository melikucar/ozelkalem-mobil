import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../api/api_istemci.dart';

/// Cihazdan seçilmiş, henüz sunucuya gönderilmemiş dosya (uygulamanın kendi klasörüne kopyalanmıştır).
class SecilenDosya {
  const SecilenDosya({
    required this.yol,
    required this.ad,
    required this.boyut,
  });

  final String yol;
  final String ad;
  final int boyut;
}

/// Seçilen dosyayı uygulama klasörüne kopyalar: seçici/kamera geçici dosyaları silinse bile gönderim kuyruğu çalışabilsin.
Future<SecilenDosya> _kopyala(String kaynak, String ad) async {
  final dizin = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'ekler'),
  );
  if (!dizin.existsSync()) dizin.createSync(recursive: true);
  final hedef = p.join(dizin.path, '${const Uuid().v4().substring(0, 8)}_$ad');
  await File(kaynak).copy(hedef);
  return SecilenDosya(yol: hedef, ad: ad, boyut: File(hedef).lengthSync());
}

Future<List<SecilenDosya>> dosyalariSec() async {
  final liste = await FilePicker.pickFiles();
  final cikti = <SecilenDosya>[];
  for (final f in liste) {
    if (f.path != null) cikti.add(await _kopyala(f.path!, f.name));
  }
  return cikti;
}

Future<List<SecilenDosya>> fotografCek() async {
  final x = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 85,
    maxWidth: 2400,
  );
  return x == null ? [] : [await _kopyala(x.path, x.name)];
}

Future<List<SecilenDosya>> galeridenSec() async {
  final liste = await ImagePicker().pickMultiImage(
    imageQuality: 85,
    maxWidth: 2400,
  );
  return [for (final x in liste) await _kopyala(x.path, x.name)];
}

String boyutYazi(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1048576).toStringAsFixed(1)} MB';
}

bool gorselMi(String ad) => const {
  'jpg',
  'jpeg',
  'jfif',
  'png',
  'gif',
  'webp',
  'bmp',
}.contains(p.extension(ad).replaceFirst('.', '').toLowerCase());

IconData dosyaIkonu(String ad) {
  switch (p.extension(ad).replaceFirst('.', '').toLowerCase()) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
    case 'docx':
    case 'rtf':
    case 'txt':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'jpg':
    case 'jpeg':
    case 'jfif':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'heic':
      return Icons.image_outlined;
    case 'mp3':
      return Icons.audiotrack_outlined;
    case 'mp4':
    case 'mov':
    case 'avi':
      return Icons.movie_outlined;
    case 'zip':
    case 'rar':
    case '7z':
      return Icons.folder_zip_outlined;
    default:
      return Icons.attach_file_rounded;
  }
}

/// Dosya ekle düğmeleri: dosya, kamera, galeri. Seçilenler [secildi] ile bildirilir.
class DosyaEkleDugmeleri extends StatelessWidget {
  const DosyaEkleDugmeleri({super.key, required this.secildi});

  final ValueChanged<List<SecilenDosya>> secildi;

  Future<void> _calistir(
    BuildContext context,
    Future<List<SecilenDosya>> Function() is_,
  ) async {
    try {
      final l = await is_();
      if (l.isNotEmpty) secildi(l);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Dosya alınamadı. İzinleri kontrol edip tekrar deneyin.',
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _calistir(context, dosyalariSec),
          icon: const Icon(Icons.attach_file_rounded),
          label: const Text('Dosya'),
        ),
        OutlinedButton.icon(
          onPressed: () => _calistir(context, fotografCek),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Kamera'),
        ),
        OutlinedButton.icon(
          onPressed: () => _calistir(context, galeridenSec),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Galeri'),
        ),
      ],
    );
  }
}

/// Dosya satırı: simge, ad, boyut; isteğe bağlı kaldır düğmesi. [tikla] verilirse açılır.
class DosyaSatiri extends StatelessWidget {
  const DosyaSatiri({
    super.key,
    required this.ad,
    this.boyut,
    this.etiket,
    this.tikla,
    this.kaldir,
    this.yukleniyor = false,
  });

  final String ad;
  final int? boyut;
  final String? etiket;
  final VoidCallback? tikla;
  final VoidCallback? kaldir;
  final bool yukleniyor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: tikla,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: tema.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: yukleniyor
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(dosyaIkonu(ad), color: tema.colorScheme.primary, size: 20),
      ),
      title: Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (boyut != null) boyutYazi(boyut!), ?etiket].join(' · '),
        style: tema.textTheme.bodySmall,
      ),
      trailing: kaldir == null
          ? null
          : IconButton(
              tooltip: 'Kaldır',
              icon: const Icon(Icons.close_rounded),
              onPressed: kaldir,
            ),
    );
  }
}

/// Sunucudaki ek dosyayı indirip açar: görseller uygulama içinde büyütülebilir, diğerleri cihazdaki uygun uygulamayla açılır.
Future<void> sunucuDosyasiniAc(
  BuildContext context,
  ApiIstemci api,
  int no,
  String ad,
  String goruntuAdi, {
  String modul = 'talepler',
}) async {
  final mesaj = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    ),
  );
  try {
    final d = await api.dosyaIndir(
      '$modul/dosya?no=$no&ad=${Uri.encodeQueryComponent(ad)}',
    );
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (gorselMi(goruntuAdi)) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 6,
                  child: Center(
                    child: Image.memory(d.bayt, fit: BoxFit.contain),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(c),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final dizin = Directory(
      p.join((await getTemporaryDirectory()).path, 'talep_dosyalari'),
    );
    if (!dizin.existsSync()) dizin.createSync(recursive: true);
    final yol = p.join(dizin.path, goruntuAdi);
    await File(yol).writeAsBytes(d.bayt);
    final s = await OpenFilex.open(yol);
    if (s.type != ResultType.done) {
      mesaj
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              s.type == ResultType.noAppToOpen
                  ? 'Bu dosya türünü açabilecek bir uygulama bulunamadı.'
                  : 'Dosya açılamadı.',
            ),
          ),
        );
    }
  } on ApiHata catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    mesaj
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            e.agHatasi
                ? 'Dosyayı indirmek için internet bağlantısı gerekir.'
                : e.mesaj,
          ),
        ),
      );
  } catch (_) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    mesaj
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Dosya açılamadı.')));
  }
}
