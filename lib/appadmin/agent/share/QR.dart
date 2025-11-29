import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class TipriQrButton extends StatelessWidget {
  /// 通常ログイン画面のURL
  final String normalUrl;

  /// 初期費用無料プラン用ログイン画面のURL
  final String freeUrl;

  const TipriQrButton({
    super.key,
    this.normalUrl = 'https://tipri.jp',
    this.freeUrl = 'https://tipri.jp/free',
  });

  static const _brandYellow = Color(0xFFFCC400);

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.qr_code),
      label: const Text('QRを表示'),
      onPressed: () => _showQrDialog(context),
      style: FilledButton.styleFrom(
        backgroundColor: _brandYellow,
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
      builder: (_) {
        bool isFree = false; // ← ダイアログ内で切り替えるフラグ

        return StatefulBuilder(
          builder: (context, setState) {
            final currentUrl = isFree ? freeUrl : normalUrl;

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.black, width: 3),
              ),
              title: Text(
                isFree ? '店舗向けログイン（初期費用無料）' : '店舗向けログイン画面',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 切り替えチップ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChoiceChip(
                            label: const Text('通常'),
                            selected: !isFree,
                            onSelected: (_) => setState(() => isFree = false),
                            selectedColor: _brandYellow,
                            labelStyle: TextStyle(
                              color: !isFree ? Colors.black : Colors.black54,
                              fontWeight: !isFree
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('初期費用無料'),
                            selected: isFree,
                            onSelected: (_) => setState(() => isFree = true),
                            selectedColor: _brandYellow,
                            labelStyle: TextStyle(
                              color: isFree ? Colors.black : Colors.black54,
                              fontWeight: isFree
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // QRコード本体
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: currentUrl,
                        version: QrVersions.auto,
                        size: 220,
                        gapless: true,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'スキャンしてアクセス',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('URLをコピー'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: currentUrl));
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('開く'),
                  onPressed: () async {
                    final uri = Uri.parse(currentUrl);
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandYellow,
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
