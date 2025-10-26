import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class TipriQrButton extends StatelessWidget {
  static const _url = 'https://tipri.jp';

  const TipriQrButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.qr_code),
      label: const Text('QRを表示'),
      onPressed: () => _showQrDialog(context),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFCC400),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
      ),
    );
  }

  Future<void> _showQrDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 3),
        ),
        title: const Text(
          '店舗向けログイン画面',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QRコード本体
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: _url,
                  version: QrVersions.auto,
                  size: 220,
                  gapless: true,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text('スキャンしてアクセス', style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('URLをコピー'),
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: _url));
              if (context.mounted) Navigator.pop(context);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('開く'),
            onPressed: () async {
              final uri = Uri.parse(_url);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFCC400),
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
