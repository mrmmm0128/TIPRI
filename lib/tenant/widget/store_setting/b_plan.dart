import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Bプラン特典（公式LINEリンクのみ）
Widget buildBPerksSection({
  required DocumentReference<Map<String, dynamic>> tenantRef,
  required DocumentReference thanksRef, // publicThanks 側にもミラー
  required TextEditingController lineUrlCtrl,
  required ButtonStyle primaryBtnStyle,
  required String tenantId, // 店舗URL生成に必要
}) {
  // Firestoreから「c_perks.lineUrl」を安全に取得
  T? _readDotPath<T>(Map<String, dynamic>? root, String path) {
    if (root == null) return null;

    // ① まず完全一致キーとして存在する場合（dot入りキーをそのまま使う）
    if (root.containsKey(path)) {
      final val = root[path];
      if (val is T) return val;
      if (T == String && val != null) return val.toString() as T;
      return null;
    }

    // ② 通常のネスト探索（既存処理）
    final segs = path.split('.');
    dynamic cur = root;
    for (final s in segs) {
      if (cur is Map) {
        cur = cur[s];
      } else {
        return null;
      }
    }

    if (cur is T) return cur;
    if (T == String && cur != null) return cur.toString() as T;
    return null;
  }

  void _hydrateOnce({
    required BuildContext ctx,
    required TextEditingController controller,
    required String? serverValue,
  }) {
    final v = (serverValue ?? '').trim();
    if (v.isEmpty || controller.text.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ctx.mounted) return;
      controller.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    });
  }

  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: tenantRef.snapshots(),
    builder: (context, snap) {
      final docData = snap.data?.data();
      final serverUrl = _readDotPath<String>(
        docData,
        'c_perks.lineUrl',
      )?.trim();

      // 初期反映（1回だけ）
      _hydrateOnce(
        ctx: context,
        controller: lineUrlCtrl,
        serverValue: serverUrl,
      );

      final isCompact = MediaQuery.of(context).size.width < 900;
      String _buildStoreUrl() => 'https://tip.tipri.jp?t=$tenantId';

      // URL確認
      Future<void> _openUrl(BuildContext ctx) async {
        final url = _buildStoreUrl();
        try {
          final ok = await launchUrlString(url);
          if (!ok && ctx.mounted) {
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(const SnackBar(content: Text('URLを開けませんでした')));
          }
        } catch (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(SnackBar(content: Text('起動に失敗しました: $e')));
          }
        }
      }

      // 保存処理
      Future<void> _saveUrl(BuildContext ctx) async {
        final v = lineUrlCtrl.text.trim();
        try {
          if (v.isEmpty) {
            await tenantRef.update({'c_perks.lineUrl': FieldValue.delete()});
            await thanksRef.update({'c_perks.lineUrl': FieldValue.delete()});
          } else {
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
                  style: const TextStyle(fontFamily: 'LINEseed'),
                ),
                backgroundColor: const Color(0xFFFCC400),
              ),
            );
          }
        }
      }

      // ---- BottomSheet（モバイル/タブレット）----
      Future<void> _openSheet() async {
        bool saving = false;
        bool checking = false;

        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) {
            final mq = MediaQuery.of(ctx);
            final viewInsets = mq.viewInsets;
            // final usableHeight =
            //       (mq.size.height -
            //               mq.padding.top -
            //               mq.padding.bottom -
            //               viewInsets.bottom)
            //           .clamp(280.0, 800.0);
            final usableHeight =
                (mq.size.height -
                        mq.padding.top -
                        mq.padding.bottom) // ← viewInsets.bottom は引かない
                    .clamp(280.0, 800.0);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: SafeArea(
                top: false,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    Future<void> save() async {
                      if (saving) return;
                      setLocal(() => saving = true);
                      try {
                        await Future<void>.delayed(Duration.zero);
                        await _saveUrl(ctx);
                        if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                      } finally {
                        if (ctx.mounted) setLocal(() => saving = false);
                      }
                    }

                    Future<void> check() async {
                      if (checking) return;
                      setLocal(() => checking = true);
                      try {
                        await Future<void>.delayed(Duration.zero);
                        await _openUrl(ctx);
                      } finally {
                        if (ctx.mounted) setLocal(() => checking = false);
                      }
                    }

                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: usableHeight),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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

                            // 現在設定値の表示
                            Row(
                              children: [
                                const Icon(Icons.info_outline, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    serverUrl?.isNotEmpty == true
                                        ? '現在設定中のURL: $serverUrl'
                                        : '現在設定中のURL: 未設定',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'LINEseed',
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

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
                                ),
                              ],
                              onSubmitted: (_) => save(),
                              autofocus: true,
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: primaryBtnStyle,
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
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: FilledButton.icon(
                                style: primaryBtnStyle,
                                onPressed: checking ? null : check,
                                icon: checking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.open_in_new),
                                label: const Text('正しく設定できたか確認する'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      }

      // ---- 本体UI ----
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
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    serverUrl?.isNotEmpty == true
                        ? '現在設定中のURL: $serverUrl'
                        : '現在設定中のURL: 未設定',
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
            StatefulBuilder(
              builder: (ctx, setLocal) {
                bool savingPc = false;
                bool checkingPc = false;

                Future<void> doSave() async {
                  if (savingPc) return;
                  setLocal(() => savingPc = true);
                  try {
                    await _saveUrl(ctx);
                  } finally {
                    if (ctx.mounted) setLocal(() => savingPc = false);
                  }
                }

                Future<void> doCheck() async {
                  if (checkingPc) return;
                  setLocal(() => checkingPc = true);
                  try {
                    await _openUrl(ctx);
                  } finally {
                    if (ctx.mounted) setLocal(() => checkingPc = false);
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          onPressed: savingPc ? null : doSave,
                          icon: savingPc
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('保存'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      serverUrl?.isNotEmpty == true
                          ? '現在設定中のURL: $serverUrl'
                          : '現在設定中のURL: 未設定',
                      style: const TextStyle(
                        fontFamily: 'LINEseed',
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FilledButton.icon(
                        style: primaryBtnStyle,
                        onPressed: checkingPc ? null : doCheck,
                        icon: checkingPc
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.open_in_new),
                        label: const Text('正しく設定できたか確認する'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
    },
  );
}
