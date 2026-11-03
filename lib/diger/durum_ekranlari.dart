import 'package:flutter/material.dart';

import '../api/oturum.dart';

class BaglantiYokEkrani extends StatelessWidget {
  const BaglantiYokEkrani({super.key, required this.oturum});

  final Oturum oturum;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 64),
                const SizedBox(height: 16),
                Text(
                  oturum.mesaj ?? 'Sunucuya ulaşılamıyor.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: oturum.baslat,
                  child: const Text('Tekrar dene'),
                ),
                TextButton(
                  onPressed: oturum.cikis,
                  child: const Text('Çıkış yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GuncellemeEkrani extends StatelessWidget {
  const GuncellemeEkrani({super.key, required this.oturum});

  final Oturum oturum;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Güncelleme gerekli',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bu sürüm (${oturum.surum}) artık desteklenmiyor. Lütfen uygulamanın yeni sürümünü yükleyin.'
                    '${oturum.guncellemeAdresi != null ? '\n\n${oturum.guncellemeAdresi}' : ''}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
