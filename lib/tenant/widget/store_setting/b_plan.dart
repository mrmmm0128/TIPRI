import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bプラン特典（公式LINEリンクのみ）
/// - モバイル/タブレット: BottomSheetで編集
/// - PC: 従来どおりインライン編集
Widget buildBPerksSection({
  required DocumentReference<Map<String, dynamic>> tenantRef,
  required DocumentReference thanksRef, // publicThanks 側にもミラーしたい場合
  required TextEditingController lineUrlCtrl,
  required ButtonStyle primaryBtnStyle,
}) {
  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: tenantRef.snapshots(),
    builder: (context, snap) {
      final data = snap.data?.data() ?? const <String, dynamic>{};

      final bPerks =
          (data['b_perks'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cPerks =
          (data['c_perks'] as Map?)?.cast<String, dynamic>() ?? const {};

      // 既に入力済みなら上書きしない
      if (lineUrlCtrl.text.isEmpty) {
        final fromB = (bPerks['lineUrl'] as String?)?.trim();
        final fromC = (cPerks['lineUrl'] as String?)?.trim();
        final v = (fromB?.isNotEmpty ?? false)
            ? fromB
            : ((fromC?.isNotEmpty ?? false) ? fromC : null);
        if (v != null) lineUrlCtrl.text = v;
      }

      final currentUrl =
          (cPerks['lineUrl'] as String?)?.trim() ??
          (bPerks['lineUrl'] as String?)?.trim() ??
          '';

      final isCompact = MediaQuery.of(context).size.width < 900; // スマホ/タブレット判定

      Future<void> _saveUrl(BuildContext ctx) async {
        final v = lineUrlCtrl.text.trim();
        try {
          if (v.isEmpty) {
            // 削除（互換のため c_perks 側を削除、必要なら b_perks も削除してOK）
            try {
              await tenantRef.update({'c_perks.lineUrl': FieldValue.delete()});
            } catch (_) {}
            try {
              await thanksRef.update({'c_perks.lineUrl': FieldValue.delete()});
            } catch (_) {}
          } else {
            // 保存（c_perks にミラー。b_perks側にも入れたければ追記）
            await tenantRef.set({
              'c_perks.lineUrl': v,
            }, SetOptions(merge: true));
            await thanksRef.set({
              'c_perks.lineUrl': v,
            }, SetOptions(merge: true));
          }
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text(
                  '公式LINEリンクを保存しました',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
                backgroundColor: Color(0xFFFCC400),
              ),
            );
          }
        } catch (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  '保存に失敗しました: $e',
                  style: TextStyle(fontFamily: 'LINEseed'),
                ),
                backgroundColor: Color(0xFFFCC400),
              ),
            );
          }
        }
      }

      Future<void> _openSheet() async {
        // 既存コントローラを使い回す（フォーカスはシート内だけ）
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (ctx, localSetState) {
                    bool saving = false;

                    Future<void> save() async {
                      if (saving) return;
                      localSetState(() => saving = true);
                      try {
                        await _saveUrl(ctx);
                        if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                      } finally {
                        localSetState(() => saving = false);
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ハンドル
                          Container(
                            height: 4,
                            width: 40,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Bプランの特典（表示用リンク）',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '閉じる',
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 現在値
                          if (currentUrl.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.info_outline, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '現在: $currentUrl',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          // 入力欄
                          TextField(
                            controller: lineUrlCtrl,
                            decoration: const InputDecoration(
                              labelText: '公式LINEリンク（任意）',
                              hintText: 'https://lin.ee/xxxxx',
                              prefixIcon: Icon(Icons.link),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'.*'),
                              ), // URLは幅広く許容
                            ],
                            onSubmitted: (_) => save(),
                            autofocus: true,
                          ),
                          const SizedBox(height: 16),

                          // 保存ボタン（局所ローディング）
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: saving ? null : save,
                                  icon: saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save),
                                  label: const Text('保存'),
                                  style: primaryBtnStyle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Bプランの特典（表示用リンク）',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          if (isCompact) ...[
            // ★ モバイル/タブレット：現在値の表示 + シートを開くボタン
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentUrl.isEmpty ? '現在: （未設定）' : '現在: $currentUrl',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: primaryBtnStyle,
                onPressed: _openSheet,
                icon: const Icon(Icons.tune),
                label: const Text('設定を開く'),
              ),
            ),
          ] else ...[
            // ★ PC：従来どおりインライン編集
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: lineUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: '公式LINEリンク（任意）',
                      hintText: 'https://lin.ee/xxxxx',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: primaryBtnStyle,
                  onPressed: () async => _saveUrl(context),
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          // BはLINEのみなので、この下の写真/動画UIはなし
        ],
      );
    },
  );
}
