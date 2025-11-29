import 'package:flutter/material.dart';

class InitialFeeCashbackPopup extends StatelessWidget {
  const InitialFeeCashbackPopup({super.key, this.onTap, this.onClose});

  /// 全体タップ時のハンドラ（タップ不可にしたい場合は null のまま）
  final VoidCallback? onTap;

  /// 右上の✕ボタン押下時のハンドラ（✕不要なら null のままでもOK）
  final VoidCallback? onClose;

  static const _borderColor = Colors.black;
  static const _borderWidth = 3.0;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFFCC400),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor, width: _borderWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign, color: Colors.black87, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'お客様の受取チップが４万円に達しました！',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    // fontFamily: 'LINEseed', // 使っていればアンコメント
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '口座情報を登録して初期費用のキャッシュバックを受け取ろう',
                  style: TextStyle(
                    // fontFamily: 'LINEseed',
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 8),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }
}
