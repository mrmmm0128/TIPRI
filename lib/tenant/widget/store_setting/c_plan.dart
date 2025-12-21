import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Cプラン特典セクション（c_perks だけ）
/// - モバイル/タブレット: BottomSheetでリンク編集（各ボタンにローディング）
/// - PC: インライン編集（各ボタンにローディング）
Widget buildCPerksSection({
  required DocumentReference<Map<String, dynamic>> tenantRef,
  required TextEditingController lineUrlCtrl,
  required TextEditingController reviewUrlCtrl,
  required String tenantId,
  required bool uploadingPhoto,
  required bool uploadingVideo,
  required bool savingExtras,
  required Uint8List? thanksPhotoPreviewBytes,
  required String? thanksPhotoUrlLocal,
  required String? thanksVideoUrlLocal,
  required VoidCallback onSaveExtras,
  required DocumentReference thanksRef,
  required void Function(BuildContext, String) onPreviewVideo,
  required ButtonStyle primaryBtnStyle,
}) {
  // ===== 便利ヘルパ：Firestoreのネストを“保存時と同じキー”で読む（例: c_perks.lineUrl） =====
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

  /// 初期表示：サーバ値を「最初の1回だけ」TextEditingControllerへ流し込む
  void _hydrateOnce({
    required BuildContext ctx,
    required TextEditingController controller,
    required String? serverValue,
  }) {
    final v = (serverValue ?? '').trim();
    if (v.isEmpty) return; // サーバ空なら何もしない
    if (controller.text.isNotEmpty) return; // 既に入力されていたら上書きしない
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
      // ★ 保存時と同じ「c_perks.lineUrl / c_perks.reviewUrl」で読む
      final serverLineUrl = _readDotPath<String>(
        docData,
        'c_perks.lineUrl',
      )?.trim();
      final serverReview = _readDotPath<String>(
        docData,
        'c_perks.reviewUrl',
      )?.trim();
      final serverVideoUrl = _readDotPath<String>(
        docData,
        'c_perks.thanksVideoUrl',
      )?.trim();

      // 初期表示：1回だけ流し込む
      _hydrateOnce(
        ctx: context,
        controller: lineUrlCtrl,
        serverValue: serverLineUrl,
      );
      _hydrateOnce(
        ctx: context,
        controller: reviewUrlCtrl,
        serverValue: serverReview,
      );

      final displayVideoUrl = (thanksVideoUrlLocal?.isNotEmpty ?? false)
          ? thanksVideoUrlLocal
          : (serverVideoUrl?.isNotEmpty ?? false)
          ? serverVideoUrl
          : null;

      final isCompact = MediaQuery.of(context).size.width < 900;
      String _buildStoreUrl() => 'https://tip.tipri.jp?t=$tenantId';

      // ---- 保存ヘルパ（保存時も “c_perks.xxx” で統一） ----
      Future<void> _saveLineUrl(BuildContext ctx) async {
        final v = lineUrlCtrl.text.trim();
        try {
          if (v.isEmpty) {
            try {
              await tenantRef.update({'c_perks.lineUrl': FieldValue.delete()});
            } catch (_) {}
            try {
              await thanksRef.update({'c_perks.lineUrl': FieldValue.delete()});
            } catch (_) {}
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
                  'LINEリンクを保存しました',
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

      Future<void> _saveReviewUrl(BuildContext ctx) async {
        final v = reviewUrlCtrl.text.trim();
        try {
          if (v.isEmpty) {
            try {
              await tenantRef.update({
                'c_perks.reviewUrl': FieldValue.delete(),
              });
            } catch (_) {}
            try {
              await thanksRef.update({
                'c_perks.reviewUrl': FieldValue.delete(),
              });
            } catch (_) {}
          } else {
            await tenantRef.set({
              'c_perks.reviewUrl': v,
            }, SetOptions(merge: true));
            await thanksRef.set({
              'c_perks.reviewUrl': v,
            }, SetOptions(merge: true));
          }
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text(
                  'Googleレビューリンクを保存しました',
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

      // ---- URL 起動ヘルパ ----
      Future<void> _openUrl(BuildContext ctx, String? url) async {
        final u = (url ?? '').trim();
        if (u.isEmpty) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(
            ctx,
          ).showSnackBar(const SnackBar(content: Text('URLが未設定です')));
          return;
        }
        final parsed = Uri.tryParse(u);
        if (parsed == null || !parsed.hasScheme) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('URLの形式が不正です（http/https を含めてください）')),
          );
          return;
        }
        try {
          final ok = await launchUrlString(u);
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

      // ---- BottomSheet（スマホ/タブレット） ----
      Future<void> _openLinksSheet() async {
        bool savingLine = false;
        bool savingReview = false;
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
            final size = mq.size;
            final viewInsets = mq.viewInsets;
            final safeH = size.height - mq.padding.top - mq.padding.bottom;
            final maxSheetHeight = (safeH * 0.9).clamp(360.0, 900.0);
            // final usable = (safeH - viewInsets.bottom).clamp(
            //   280.0,
            //   maxSheetHeight,
            // );
            final usable = safeH.clamp(280.0, maxSheetHeight);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: SafeArea(
                top: false,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    Future<void> saveLine() async {
                      if (savingLine) return;
                      setLocal(() => savingLine = true);
                      try {
                        await Future<void>.delayed(Duration.zero);
                        await _saveLineUrl(ctx);
                      } finally {
                        if (ctx.mounted) setLocal(() => savingLine = false);
                      }
                    }

                    Future<void> saveReview() async {
                      if (savingReview) return;
                      setLocal(() => savingReview = true);
                      try {
                        await Future<void>.delayed(Duration.zero);
                        await _saveReviewUrl(ctx);
                      } finally {
                        if (ctx.mounted) setLocal(() => savingReview = false);
                      }
                    }

                    Future<void> openCheck() async {
                      if (checking) return;
                      setLocal(() => checking = true);
                      try {
                        await Future<void>.delayed(Duration.zero);
                        await _openUrl(ctx, _buildStoreUrl());
                      } finally {
                        if (ctx.mounted) setLocal(() => checking = false);
                      }
                    }

                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: usable.toDouble()),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
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
                                  'リンクの設定',
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

                            // 現在値の簡易表示（保存と同じキーでの読取値を表示）
                            Row(
                              children: [
                                const Icon(Icons.info_outline, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '現在: ${serverLineUrl?.isNotEmpty == true ? "LINE 設定済" : "LINE 未設定"} / '
                                    '${serverReview?.isNotEmpty == true ? "レビュー 設定済" : "レビュー 未設定"}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // LINE
                            TextField(
                              controller: lineUrlCtrl,
                              decoration: const InputDecoration(
                                labelText: '公式LINEリンク',
                                hintText: 'https://lin.ee/xxxxx',
                                prefixIcon: Icon(Icons.link),
                              ),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'.*'),
                                ),
                              ],
                              onSubmitted: (_) => saveLine(),
                              autofocus: true,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: savingLine ? null : saveLine,
                                icon: savingLine
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save),
                                label: const Text('LINEリンクを保存'),
                                style: primaryBtnStyle,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // レビュー
                            TextField(
                              controller: reviewUrlCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Googleレビューリンク',
                                hintText: 'https://g.page/r/xxxxx/review',
                                prefixIcon: Icon(Icons.reviews),
                              ),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'.*'),
                                ),
                              ],
                              onSubmitted: (_) => saveReview(),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: savingReview ? null : saveReview,
                                icon: savingReview
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save),
                                label: const Text('レビューリンクを保存'),
                                style: primaryBtnStyle,
                              ),
                            ),

                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FilledButton.icon(
                                  onPressed: checking ? null : openCheck,
                                  icon: checking
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.open_in_new),
                                  label: const Text(
                                    '正しく設定できたか確認する',
                                    style: TextStyle(
                                      fontFamily: "LINEseed",
                                      fontSize: 14,
                                    ),
                                  ),
                                  style: primaryBtnStyle,
                                ),
                              ],
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
          const Divider(height: 1, color: Colors.black87),
          const SizedBox(height: 16),
          const Text(
            'チップ送信者向け案内リンク',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          if (isCompact) ...[
            // モバイル/タブレット：現在値 + 設定を開く
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'LINE: ${serverLineUrl?.isNotEmpty == true ? "設定済" : "未設定"} / '
                    'レビュー: ${serverReview?.isNotEmpty == true ? "設定済" : "未設定"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _openLinksSheet,
                icon: const Icon(Icons.tune),
                label: const Text('設定を開く'),
                style: primaryBtnStyle,
              ),
            ),
          ] else ...[
            // PC：インライン（各ボタンに局所ローディング）
            // LINE保存
            StatefulBuilder(
              builder: (ctx, setLocal) {
                bool savingLinePc = false;
                Future<void> doSave() async {
                  if (savingLinePc) return;
                  setLocal(() => savingLinePc = true);
                  try {
                    await Future<void>.delayed(Duration.zero);
                    await _saveLineUrl(ctx);
                  } finally {
                    if (ctx.mounted) setLocal(() => savingLinePc = false);
                  }
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: lineUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: '公式LINEリンク',
                          hintText: 'https://lin.ee/xxxxx',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: savingLinePc ? null : doSave,
                      icon: savingLinePc
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('保存'),
                      style: primaryBtnStyle,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 8),

            // Review保存
            StatefulBuilder(
              builder: (ctx, setLocal) {
                bool savingReviewPc = false;
                Future<void> doSave() async {
                  if (savingReviewPc) return;
                  setLocal(() => savingReviewPc = true);
                  try {
                    await Future<void>.delayed(Duration.zero);
                    await _saveReviewUrl(ctx);
                  } finally {
                    if (ctx.mounted) setLocal(() => savingReviewPc = false);
                  }
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: reviewUrlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Googleレビューリンク',
                          hintText: 'https://g.page/r/xxxxx/review',
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: savingReviewPc ? null : doSave,
                      icon: savingReviewPc
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('保存'),
                      style: primaryBtnStyle,
                    ),
                  ],
                );
              },
            ),

            // 確認ボタン（PC）
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (ctx, setLocal) {
                bool checkingPc = false;
                Future<void> doOpen() async {
                  if (checkingPc) return;
                  setLocal(() => checkingPc = true);
                  try {
                    await Future<void>.delayed(Duration.zero);
                    await _openUrl(ctx, _buildStoreUrl());
                  } finally {
                    if (ctx.mounted) setLocal(() => checkingPc = false);
                  }
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: checkingPc ? null : doOpen,
                      icon: checkingPc
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new),
                      label: const Text('正しく設定できたか確認する'),
                      style: primaryBtnStyle,
                    ),
                  ],
                );
              },
            ),
          ],

          // const Divider(height: 1, color: Colors.black87),
          // const SizedBox(height: 16),
          // const Text('感謝の動画', style: TextStyle(fontWeight: FontWeight.w600)),
          // const SizedBox(height: 16),

          // // 動画（表示のみ）
          // Row(
          //   crossAxisAlignment: CrossAxisAlignment.center,
          //   mainAxisAlignment: MainAxisAlignment.center,
          //   children: [
          //     Container(
          //       width: 96,
          //       height: 96,
          //       alignment: Alignment.center,
          //       decoration: BoxDecoration(
          //         color: Colors.grey.shade200,
          //         borderRadius: BorderRadius.circular(12),
          //         border: Border.all(color: const Color(0x11000000)),
          //       ),
          //       child: uploadingVideo
          //           ? const SizedBox(
          //               width: 24,
          //               height: 24,
          //               child: CircularProgressIndicator(strokeWidth: 2),
          //             )
          //           : ((displayVideoUrl ?? '').isNotEmpty
          //                 ? const Icon(Icons.play_circle_fill, size: 24)
          //                 : const Icon(Icons.movie, size: 20)),
          //     ),
          //     const SizedBox(width: 12),
          //     const Expanded(child: Text('スタッフ詳細画面から動画を登録してください。')),
          //   ],
          // ),
        ],
      );
    },
  );
}
